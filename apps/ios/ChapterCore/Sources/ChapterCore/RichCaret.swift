// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

/// A collapsed cursor in the original document, in ProseMirror terms: the path
/// of a textblock plus its parent offset (UTF-16 code units of text; every
/// non-text inline node, such as an entry link or hard break, counts as 1).
public struct RichCaret: Codable, Equatable, Hashable {
    public let block: [Int]
    public let offset: Int
    public init(block: [Int], offset: Int) { self.block = block; self.offset = offset }
}

public extension RichDocument {
    static let textblockTypes: Set<String> = ["paragraph", "heading", "codeBlock"]

    private func nodeValue(at path: [Int]) -> JSONValue? {
        var value = root
        for index in path {
            let children = value["content"].array
            guard Self.containers.contains(value["type"].string ?? ""), children.indices.contains(index) else { return nil }
            value = children[index]
        }
        return value
    }
    private static func inlineSize(_ node: JSONValue) -> Int { node["type"].string == "text" ? (node["text"].string ?? "").utf16.count : 1 }

    /// Cursor from an editable leaf (a text node, or an empty textblock) and a
    /// UTF-16 offset inside that leaf's text, e.g. from the native text editor.
    func caret(leaf path: [Int], utf16Offset: Int) throws -> RichCaret {
        guard let leaf = nodeValue(at: path), utf16Offset >= 0 else { throw ChapterError.unsupported }
        if Self.textblockTypes.contains(leaf["type"].string ?? "") {
            guard leaf["content"].array.isEmpty, utf16Offset == 0 else { throw ChapterError.unsupported }
            return RichCaret(block: path, offset: 0)
        }
        guard leaf["type"].string == "text", let index = path.last, let block = nodeValue(at: Array(path.dropLast())),
              Self.textblockTypes.contains(block["type"].string ?? ""), utf16Offset <= Self.inlineSize(leaf) else { throw ChapterError.unsupported }
        let before = block["content"].array.prefix(index).reduce(0) { $0 + Self.inlineSize($1) }
        return RichCaret(block: Array(path.dropLast()), offset: before + utf16Offset)
    }

    /// Splits a textblock's inline content at a parent offset, like ProseMirror.
    private func split(_ caret: RichCaret) throws -> (block: [String: JSONValue], left: [JSONValue], right: [JSONValue]) {
        guard let value = nodeValue(at: caret.block), case .object(let fields) = value, Self.textblockTypes.contains(fields["type"]?.string ?? ""), caret.offset >= 0 else { throw ChapterError.unsupported }
        var left: [JSONValue] = [], right: [JSONValue] = [], position = 0
        for node in value["content"].array {
            let size = Self.inlineSize(node)
            if position + size <= caret.offset { left.append(node) }
            else if position >= caret.offset { right.append(node) }
            else {
                // Inside a text node: both halves keep every original field and mark.
                guard case .object(var head) = node, let text = head["text"]?.string else { throw ChapterError.unsupported }
                let utf16 = text.utf16, cut = utf16.index(utf16.startIndex, offsetBy: caret.offset - position)
                guard cut.samePosition(in: text.unicodeScalars) != nil else { throw ChapterError.unsupported }
                var tail = head
                head["text"] = .string(String(text[..<cut])); tail["text"] = .string(String(text[cut...]))
                left.append(.object(head)); right.append(.object(tail))
            }
            position += size
        }
        guard caret.offset <= position else { throw ChapterError.unsupported }
        return (fields, left, right)
    }
    private static func marksKey(_ node: JSONValue) -> Data? {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(node["marks"].array)
    }
    /// ProseMirror joins adjacent text nodes with the same marks; with node-first
    /// content only the trailing seam can create a new pair. The original node's fields win.
    private static func join(_ a: JSONValue, _ b: JSONValue, keepFirst: Bool) -> JSONValue? {
        guard a["type"].string == "text", b["type"].string == "text", let ka = marksKey(a), ka == marksKey(b),
              case .object(var fields) = keepFirst ? a : b else { return nil }
        fields["text"] = .string((a["text"].string ?? "") + (b["text"].string ?? ""))
        return .object(fields)
    }
    private mutating func replacing(_ path: [Int], with replacement: [JSONValue]) throws {
        func go(_ node: JSONValue, _ rest: ArraySlice<Int>) throws -> JSONValue {
            guard case .object(var fields) = node, let first = rest.first else { throw ChapterError.unsupported }
            var children = node["content"].array
            guard children.indices.contains(first) else { throw ChapterError.unsupported }
            if rest.count == 1 { children.replaceSubrange(first...first, with: replacement) }
            else { children[first] = try go(children[first], rest.dropFirst()) }
            fields["content"] = .array(children); return .object(fields)
        }
        let next = try go(root, ArraySlice(path))
        self = try RichDocument(json: String(decoding: JSONEncoder().encode(next), as: UTF8.self))
    }

    /// TipTap insertContentAt(cursor, inline nodes) → ProseMirror replaceWith.
    mutating func insertInline(_ nodes: [JSONValue], at caret: RichCaret) throws {
        guard !nodes.isEmpty, nodes.allSatisfy({ if case .object = $0, let t = $0["type"].string { return !Self.textblockTypes.contains(t) && !["doc", "table", "bulletList", "orderedList", "taskList", "blockquote"].contains(t) }; return false }) else { throw ChapterError.unsupported }
        // Content that starts with plain text takes TipTap's insertText path
        // (which keeps stored marks); only node-first content is claimed here.
        guard nodes[0]["type"].string != "text" else { throw ChapterError.unsupported }
        let (fields0, left, right0) = try split(caret)
        var fields = fields0, right = right0
        guard fields["type"]?.string != "codeBlock" else { throw ChapterError.unsupported }
        var middle = nodes
        if let first = right.first, let joined = Self.join(middle[middle.count - 1], first, keepFirst: false) { right.removeFirst(); middle[middle.count - 1] = joined }
        fields["content"] = .array(left + middle + right)
        try replacing(caret.block, with: [.object(fields)])
    }

    /// TipTap insertContentAt(cursor, template blocks) at a top-level textblock:
    /// an empty textblock is replaced; otherwise it splits, dropping an empty half.
    mutating func insertBlocks(_ blocks: [JSONValue], at caret: RichCaret) throws {
        guard !blocks.isEmpty, caret.block.count == 1, blocks.allSatisfy({ if case .object = $0, let t = $0["type"].string { return t != "text" && t != "doc" }; return false }) else { throw ChapterError.unsupported }
        let (fields, left, right) = try split(caret)
        guard fields["type"]?.string != "codeBlock" else { throw ChapterError.unsupported }
        func half(_ content: [JSONValue]) -> JSONValue { var copy = fields; copy["content"] = .array(content); return .object(copy) }
        try replacing(caret.block, with: (left.isEmpty ? [] : [half(left)]) + blocks + (right.isEmpty ? [] : [half(right)]))
    }
}

public extension VaultRecord {
    /// Original wikilink insertEntryLink at the cursor: [entryLink, " "].
    func insertingEntryLink(to target: VaultRecord, at caret: RichCaret, expected: String, now: Date = Date()) throws -> VaultRecord {
        guard target.kind == "entry", !target.deleted, !Data(target.id.utf8).elementsEqual(id.utf8), !target.id.isEmpty else { throw ChapterError.unsupported }
        let link: JSONValue = .object(["type": .string("entryLink"), "attrs": .object(["entryId": .string(target.id), "label": .string(EntryLinkAuthoring.label(for: target))])])
        return try editingRichDocument(expected: expected, now: now) { try $0.insertInline([link, .object(["type": .string("text"), "text": .string(" ")])], at: caret) }
    }
    /// Original Editor insertTemplate: the template's top-level blocks at the cursor.
    /// A template without a readable rich body inserts nothing (refused here).
    func insertingTemplate(_ template: VaultRecord, at caret: RichCaret, expected: String, now: Date = Date()) throws -> VaultRecord {
        guard template.kind == "template", !template.deleted, let json = template.body["bodyJson"]?.string else { throw ChapterError.unsupported }
        let blocks = try RichDocument(json: json).root["content"].array
        guard !blocks.isEmpty else { throw ChapterError.unsupported }
        return try editingRichDocument(expected: expected, now: now) { try $0.insertBlocks(blocks, at: caret) }
    }
}
