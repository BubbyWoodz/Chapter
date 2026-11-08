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
    public func encoded() throws -> String { String(decoding: try JSONEncoder().encode(root), as: UTF8.self) }
    public var node: RichNode { RichNode(value: root, path: []) }
    public var textLeaves: [RichNode] {
        func walk(_ node: RichNode) -> [RichNode] {
            if node.type == "text" { return [node] }
            return Self.containers.contains(node.type) ? node.children.flatMap(walk) : []
        }
        return walk(node)
    }
    public mutating func replaceText(at path: [Int], with text: String) throws {
        guard textLeaves.contains(where: { $0.path == path }) else { throw ChapterError.unsupported }
        root = try patch(root, path: ArraySlice(path)) { node in
            guard case .object(var fields) = node, fields["type"]?.string == "text" else { throw ChapterError.unsupported }
            if text.isEmpty { return nil } // remove the selected run; keep its parent/other runs
            fields["text"] = .string(text); return .object(fields)
        }
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
    public var id: String { entryID + ":" + path.map(String.init).joined(separator: "/") }
    public init(entryID: String, path: [Int], expectedDocument: String, text: String) {
        self.entryID = entryID; self.path = path; self.expectedDocument = expectedDocument; self.text = text
    }
}
