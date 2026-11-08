// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

/// The original ProseMirror JSON is the source of truth. Native edits patch a
/// selected text node/task attribute, never round-trip through Markdown or HTML.
public struct RichDocument {
    public private(set) var root: JSONValue
    public static let containers: Set<String> = ["doc", "paragraph", "heading", "bulletList", "orderedList", "listItem", "taskList", "taskItem", "blockquote", "codeBlock", "table", "tableRow", "tableCell", "tableHeader"]
    public init(json: String) throws {
        guard json.utf8.count <= 8 * 1024 * 1024 else { throw ChapterError.unsupported }
        root = try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
        guard root["type"].string == "doc" else { throw ChapterError.corruptData }
        var count = 0
        func validate(_ node: JSONValue, _ depth: Int) throws {
            count += 1
            guard depth < 128, count <= 100_000, case .object = node, let type = node["type"].string else { throw ChapterError.corruptData }
            // Unknown node payloads are opaque, not interpreted or made editable.
            if Self.containers.contains(type) {
                if case .null = node["content"] { return }
                guard case .array(let children) = node["content"] else { throw ChapterError.corruptData }
                for child in children { try validate(child, depth + 1) }
            } else if type == "text" {
                guard node["text"].string != nil else { throw ChapterError.corruptData }
            }
        }
        try validate(root, 0)
    }
    public func encoded() throws -> String {
        let data = try JSONEncoder().encode(root)
        guard data.count <= 8 * 1024 * 1024 else { throw ChapterError.unsupported }
        return String(decoding: data, as: UTF8.self)
    }
    public var node: RichNode { RichNode(value: root, path: []) }
    public var textLeaves: [RichNode] {
        func walk(_ node: RichNode) -> [RichNode] {
            if node.type == "text" { return [node] }
            return Self.containers.contains(node.type) ? node.children.flatMap(walk) : []
        }
        return walk(node)
    }
    /// Empty original text blocks remain editable after their last run is removed.
    public var editableTextNodes: [RichNode] {
        func walk(_ node: RichNode) -> [RichNode] {
            if node.type == "text" { return [node] }
            if ["paragraph", "heading", "codeBlock"].contains(node.type), node.value["content"].array.isEmpty { return [node] }
            return Self.containers.contains(node.type) ? node.children.flatMap(walk) : []
        }
        return walk(node)
    }
    public static let editableMarks: Set<String> = ["bold", "italic", "underline", "strike", "code"]
    public mutating func replaceText(at path: [Int], with text: String, marks: [JSONValue]? = nil) throws {
        guard text.utf8.count <= 8 * 1024 * 1024, let original = editableTextNodes.first(where: { $0.path == path }) else { throw ChapterError.unsupported }
        if let marks {
            var parent = node
            for index in path.dropLast() { guard parent.children.indices.contains(index) else { throw ChapterError.unsupported }; parent = parent.children[index] }
            guard marks.isEmpty || (parent.type != "codeBlock" && original.type != "codeBlock") else { throw ChapterError.unsupported }
            guard marks.count <= 1024, (!marks.contains(where: { $0["type"].string == "code" }) || marks.count == 1), marks.allSatisfy({ if case .object = $0 { return $0["type"].string != nil }; return false }) else { throw ChapterError.unsupported }
            // Native formatting may change only the explicitly supported marks.
            let opaque: (JSONValue) -> Bool = { !Self.editableMarks.contains($0["type"].string ?? "") }
            guard marks.filter(opaque) == original.value["marks"].array.filter(opaque) else { throw ChapterError.unsupported }
        }
        root = try patch(root, path: ArraySlice(path)) { node in
            guard case .object(var fields) = node else { throw ChapterError.unsupported }
            if original.type == "text" {
                if text.isEmpty { return nil }
                fields["text"] = .string(text)
                if let marks { fields["marks"] = .array(marks) }
            } else {
                guard original.value["content"].array.isEmpty else { throw ChapterError.unsupported }
                var leaf: [String: JSONValue] = ["type": .string("text"), "text": .string(text)]
                if let marks { leaf["marks"] = .array(marks) }
                fields["content"] = .array(text.isEmpty ? [] : [.object(leaf)])
            }
            return .object(fields)
        }
    }
    public mutating func appendTextBlock(text: String, style: RichBlockStyle) throws {
        guard !text.isEmpty, text.utf8.count <= 8 * 1024 * 1024, case .object(var fields) = root else { throw ChapterError.unsupported }
        let leaf: JSONValue = .object(["type": .string("text"), "text": .string(text)])
        let paragraph: JSONValue = .object(["type": .string("paragraph"), "content": .array([leaf])])
        let block: JSONValue
        switch style {
        case .paragraph: block = paragraph
        case .heading1, .heading2, .heading3:
            block = .object(["type": .string("heading"), "attrs": .object(["level": .number(Double(style.headingLevel))]), "content": .array([leaf])])
        case .codeBlock: block = .object(["type": .string("codeBlock"), "content": .array([leaf])])
        case .blockquote: block = .object(["type": .string("blockquote"), "content": .array([paragraph])])
        case .bulletList, .orderedList, .taskList:
            var item: [String: JSONValue] = ["type": .string(style == .taskList ? "taskItem" : "listItem"), "content": .array([paragraph])]
            if style == .taskList { item["attrs"] = .object(["checked": .bool(false)]) }
            block = .object(["type": .string(style.rawValue), "content": .array([.object(item)])])
        }
        var children = fields["content"]?.array ?? []; children.append(block)
        fields["content"] = .array(children)
        // Enforce the same document/complexity limits as imported original trees.
        self = try RichDocument(json: String(decoding: JSONEncoder().encode(JSONValue.object(fields)), as: UTF8.self))
    }
    public mutating func appendMedia(_ attributes: [String: JSONValue]) throws {
        guard case .object(var fields) = root, fields["type"]?.string == "doc" else { throw ChapterError.corruptData }
        var content = fields["content"]?.array ?? []
        content.append(.object(["type": .string("mediaAttachment"), "attrs": .object(attributes)]))
        fields["content"] = .array(content); root = .object(fields)
    }
    public mutating func toggleTask(at path: [Int]) throws {
        root = try patch(root, path: ArraySlice(path)) { node in
            guard case .object(var fields) = node, fields["type"]?.string == "taskItem" else { throw ChapterError.unsupported }
            var attrs: [String: JSONValue]
            if case .object(let original) = fields["attrs"] { attrs = original }
            else if fields["attrs"] == nil { attrs = [:] }
            else { throw ChapterError.corruptData }
            let checked: Bool
            if case .bool(let value) = attrs["checked"] { checked = value }
            else if attrs["checked"] == nil { checked = false }
            else { throw ChapterError.corruptData }
            attrs["checked"] = .bool(!checked); fields["attrs"] = .object(attrs); return .object(fields)
        }
    }
    private func patch(_ node: JSONValue, path: ArraySlice<Int>, change: (JSONValue) throws -> JSONValue?) throws -> JSONValue {
        guard let first = path.first else {
            guard let result = try change(node) else { throw ChapterError.unsupported }; return result
        }
        guard case .object(var fields) = node, let type = fields["type"]?.string,
              Self.containers.contains(type), case .array(var children) = fields["content"], children.indices.contains(first) else { throw ChapterError.unsupported }
        if path.count == 1 {
            if let result = try change(children[first]) { children[first] = result } else { children.remove(at: first) }
        } else { children[first] = try patch(children[first], path: path.dropFirst(), change: change) }
        fields["content"] = .array(children); return .object(fields)
    }
    /// Mirrors the original web docToText markers/newlines for previews/search.
    public var plainText: String {
        var out = ""
        func walk(_ node: RichNode) {
            let attrs = node.value["attrs"]
            switch node.type {
            case "text": out += node.text
            case "mediaAttachment":
                let kind = attrs["kind"].string ?? "", name = attrs["name"].string ?? ""
                if kind == "audio" { out += "🎙 audio" }
                else if kind == "image" { out += "🖼 image" + (name.isEmpty ? "" : " " + name) }
                else if kind == "file" { out += "📎" + (name.isEmpty ? " file" : " " + name) }
                else { out += "🎬 video" }
                if let transcript = attrs["transcript"].string, !transcript.isEmpty { out += "\n" + transcript + "\n" }
            case "mediaGallery": let n = attrs["images"].array.count; out += n == 1 ? "🖼 1 photo" : "🖼 \(n) photos"
            case "inlineMath", "blockMath": out += attrs["latex"].string ?? ""
            case "entryLink": if let label = attrs["label"].string { out += "🔗 " + label }
            case "videoInterview":
                let name = attrs["typeName"].string ?? ""; out += "🎬 " + (name.isEmpty ? "video interview" : name) + "\n"
                for card in attrs["cards"].array {
                    for key in ["q", "transcript"] { if let text = card[key].string, !text.isEmpty { out += text + "\n" } }
                }
            case "locationMap":
                if let from = attrs["from"]["label"].string { let to = attrs["to"]["label"].string ?? ""; out += "📍 " + from + (to.isEmpty ? "" : " → " + to) }
            default: break
            }
            // Reading a preview may inspect children, but unsupported children are never editable.
            node.children.forEach(walk)
            if !["text", "doc", "inlineMath", "entryLink"].contains(node.type) { out += "\n" }
        }
        walk(node)
        // ECMAScript trim includes BOM but not NEL; Foundation's whitespace set
        // differs. Match the actual web preview, including unusual imported text.
        let whitespace = CharacterSet(charactersIn: "\u{0009}\u{000A}\u{000B}\u{000C}\u{000D}\u{0020}\u{00A0}\u{1680}\u{2000}\u{2001}\u{2002}\u{2003}\u{2004}\u{2005}\u{2006}\u{2007}\u{2008}\u{2009}\u{200A}\u{2028}\u{2029}\u{202F}\u{205F}\u{3000}\u{FEFF}")
        return out.replacingOccurrences(of: "\n{2,}", with: "\n", options: .regularExpression).trimmingCharacters(in: whitespace)
    }
}

public struct RichNode: Identifiable {
    public let value: JSONValue
    public let path: [Int]
    public var id: String { path.map(String.init).joined(separator: "/") }
    public var type: String { value["type"].string ?? "unknown" }
    public var text: String { value["text"].string ?? "" }
    public var children: [RichNode] { value["content"].array.enumerated().map { RichNode(value: $0.element, path: path + [$0.offset]) } }
}

extension VaultRecord {
    public func editingRichDocument(expected: String, now: Date = Date(), edit: (inout RichDocument) throws -> Void) throws -> VaultRecord {
        guard kind == "entry", !deleted, body["bodyJson"]?.string == expected else { throw ChapterError.conflict }
        var document = try RichDocument(json: expected); try edit(&document)
        document = try RichDocument(json: document.encoded())
        var next = self
        next.clock = try ProtocolNumbers.nextClock(after: clock, now: now); next.dirty = true
        next.body["bodyJson"] = .string(try document.encoded()); next.body["bodyText"] = .string(document.plainText)
        next.body["updatedAt"] = .number(Double(next.clock))
        return next
    }
}

public struct RichDraft: Codable, Identifiable, Equatable {
    public let entryID: String
    public let path: [Int]
    public let expectedDocument: String
    public var text: String
    public var marks: [JSONValue]? = nil
    public var newBlockStyle: RichBlockStyle? = nil
    public var id: String { entryID + ":" + (newBlockStyle == nil ? path.map(String.init).joined(separator: "/") : "new-block") }
    public init(entryID: String, path: [Int], expectedDocument: String, text: String) {
        self.entryID = entryID; self.path = path; self.expectedDocument = expectedDocument; self.text = text
    }
}

public enum RichBlockStyle: String, Codable, CaseIterable {
    case paragraph, heading1, heading2, heading3, blockquote, bulletList, orderedList, taskList, codeBlock
    public var title: String {
        switch self {
        case .paragraph: return "Paragraph"
        case .heading1: return "Heading 1"
        case .heading2: return "Heading 2"
        case .heading3: return "Heading 3"
        case .blockquote: return "Quote"
        case .bulletList: return "Bulleted list"
        case .orderedList: return "Numbered list"
        case .taskList: return "Task list"
        case .codeBlock: return "Code block"
        }
    }
    fileprivate var headingLevel: Int { self == .heading1 ? 1 : self == .heading2 ? 2 : 3 }
}

extension RichDraft {
    public static func newBlock(entryID: String, expectedDocument: String) -> RichDraft {
        var draft = RichDraft(entryID: entryID, path: [], expectedDocument: expectedDocument, text: "")
        draft.newBlockStyle = .paragraph; return draft
    }
    public func togglingMark(_ type: String) throws -> RichDraft {
        guard newBlockStyle == nil, RichDocument.editableMarks.contains(type),
              let node = try RichDocument(json: expectedDocument).editableTextNodes.first(where: { $0.path == path }) else { throw ChapterError.unsupported }
        // Code blocks cannot acquire inline marks in the original editor schema.
        let parentPath = node.type == "text" ? Array(path.dropLast()) : path
        let document = try RichDocument(json: expectedDocument)
        var parent = document.node
        for index in parentPath { guard parent.children.indices.contains(index) else { throw ChapterError.unsupported }; parent = parent.children[index] }
        guard parent.type != "codeBlock" else { throw ChapterError.unsupported }
        var copy = self; var values = marks ?? node.value["marks"].array
        if values.contains(where: { $0["type"].string == type }) { values.removeAll { $0["type"].string == type } }
        else {
            // Original TipTap inline code excludes all other marks. Never erase
            // an opaque mark/link just to add code; explicit unsupported is safer.
            if type == "code" {
                guard values.allSatisfy({ RichDocument.editableMarks.contains($0["type"].string ?? "") }) else { throw ChapterError.unsupported }
                values.removeAll()
            } else { values.removeAll { $0["type"].string == "code" } }
            values.append(node.value["marks"].array.first(where: { $0["type"].string == type }) ?? .object(["type": .string(type)]))
        }
        copy.marks = values; return copy
    }
    public var supportsFormatting: Bool {
        guard newBlockStyle == nil, let document = try? RichDocument(json: expectedDocument),
              let node = document.editableTextNodes.first(where: { $0.path == path }) else { return false }
        let parentPath = node.type == "text" ? Array(path.dropLast()) : path
        var parent = document.node
        for index in parentPath { guard parent.children.indices.contains(index) else { return false }; parent = parent.children[index] }
        return parent.type != "codeBlock"
    }
    public func hasMark(_ type: String) -> Bool {
        let original = try? RichDocument(json: expectedDocument).editableTextNodes.first(where: { $0.path == path })
        return (marks ?? original?.value["marks"].array ?? []).contains { $0["type"].string == type }
    }
    public func applying(to record: VaultRecord, now: Date = Date()) throws -> VaultRecord {
        guard record.id == entryID else { throw ChapterError.conflict }
        return try record.editingRichDocument(expected: expectedDocument, now: now) { document in
            if let style = newBlockStyle {
                guard path.isEmpty, marks == nil else { throw ChapterError.unsupported }
                try document.appendTextBlock(text: text, style: style)
            } else { try document.replaceText(at: path, with: text, marks: marks) }
        }
    }
}
