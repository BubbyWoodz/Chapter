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

    internal func nodeValue(at path: [Int]) -> JSONValue? {
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
    internal static func join(_ a: JSONValue, _ b: JSONValue, keepFirst: Bool) -> JSONValue? {
        guard a["type"].string == "text", b["type"].string == "text", let ka = marksKey(a), ka == marksKey(b),
              case .object(var fields) = keepFirst ? a : b else { return nil }
        fields["text"] = .string((a["text"].string ?? "") + (b["text"].string ?? ""))
        return .object(fields)
    }
    internal mutating func replacing(_ path: [Int], with replacement: [JSONValue]) throws {
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

/// Formatting a selection, as the original toolbar's TipTap toggleMark does it.
/// The native editor edits one text leaf at a time, so a selection is a UTF-16
/// range inside that leaf; there TipTap's isMarkActive is simply "this leaf
/// already has the mark". Verified against the real TipTap Editor (rich-selection.json).
public extension RichDocument {
    /// Original schema mark rank (ProseMirror keeps every mark set in this order).
    static let markOrder = ["link", "bold", "code", "italic", "strike", "underline"]
    /// Original schema exclusions: inline code excludes every other mark.
    static let markExclusions: [String: Set<String>] = ["code": ["link", "bold", "italic", "strike", "underline"]]
    /// ProseMirror Mark.addToSet: the new mark goes before the first existing
    /// mark of higher schema rank. Existing marks are never reordered, and marks
    /// unknown to this build keep their place.
    static func insertingMark(_ mark: JSONValue, into marks: [JSONValue]) -> [JSONValue] {
        guard let rank = markOrder.firstIndex(of: mark["type"].string ?? "") else { return marks + [mark] }
        var result = marks
        let at = marks.firstIndex { markOrder.firstIndex(of: $0["type"].string ?? "").map { $0 > rank } ?? false } ?? marks.count
        result.insert(mark, at: at); return result
    }

    mutating func toggleMark(_ type: String, leaf path: [Int], utf16Range range: Range<Int>) throws {
        guard Self.editableMarks.contains(type), !range.isEmpty, range.lowerBound >= 0, let index = path.last,
              let blockValue = nodeValue(at: Array(path.dropLast())), case .object(var block) = blockValue,
              Self.textblockTypes.contains(block["type"]?.string ?? ""), block["type"]?.string != "codeBlock",
              let leaf = nodeValue(at: path), leaf["type"].string == "text", case .object(let fields) = leaf,
              let text = fields["text"]?.string, range.upperBound <= text.utf16.count else { throw ChapterError.unsupported }
        let utf16 = text.utf16
        let start = utf16.index(utf16.startIndex, offsetBy: range.lowerBound), end = utf16.index(utf16.startIndex, offsetBy: range.upperBound)
        guard start.samePosition(in: text.unicodeScalars) != nil, end.samePosition(in: text.unicodeScalars) != nil else { throw ChapterError.unsupported }
        let marks = leaf["marks"].array, name: (JSONValue) -> String = { $0["type"].string ?? "" }
        var changed: [JSONValue]
        if marks.contains(where: { name($0) == type }) {
            changed = marks.filter { name($0) != type }
        } else {
            // A mark that excludes this one makes TipTap a no-op; refuse rather than write nothing.
            guard !marks.contains(where: { Self.markExclusions[name($0)]?.contains(type) == true }) else { throw ChapterError.unsupported }
            let excluded = Self.markExclusions[type] ?? []
            // Adding code would erase links or other non-native marks; never do that silently.
            guard !marks.contains(where: { excluded.contains(name($0)) && !Self.editableMarks.contains(name($0)) }) else { throw ChapterError.unsupported }
            changed = Self.insertingMark(.object(["type": .string(type)]), into: marks.filter { !excluded.contains(name($0)) })
        }
        func piece(_ part: Substring, marks: [JSONValue]?) -> JSONValue {
            var copy = fields; copy["text"] = .string(String(part))
            if let marks { if marks.isEmpty { copy.removeValue(forKey: "marks") } else { copy["marks"] = .array(marks) } }
            return .object(copy)
        }
        var pieces: [JSONValue] = []
        if start > text.startIndex { pieces.append(piece(text[..<start], marks: nil)) }
        let selected = pieces.count
        pieces.append(piece(text[start..<end], marks: changed))
        if end < text.endIndex { pieces.append(piece(text[end...], marks: nil)) }
        var content = blockValue["content"].array
        content.replaceSubrange(index...index, with: pieces)
        // ProseMirror joins equal-mark text at the step's seams; the left node's fields win.
        let middle = index + selected
        if middle + 1 < content.count, let joined = Self.join(content[middle], content[middle + 1], keepFirst: true) { content[middle] = joined; content.remove(at: middle + 1) }
        if middle > 0, let joined = Self.join(content[middle - 1], content[middle], keepFirst: true) { content[middle - 1] = joined; content.remove(at: middle) }
        block["content"] = .array(content)
        try replacing(Array(path.dropLast()), with: [.object(block)])
    }
}

public extension VaultRecord {
    /// Original wikilink insertEntryLink at the cursor: [entryLink, " "].
    func insertingEntryLink(to target: VaultRecord, at caret: RichCaret, expected: String, now: Date = Date()) throws -> VaultRecord {
        guard target.kind == "entry", !target.deleted, !Data(target.id.utf8).elementsEqual(id.utf8), !target.id.isEmpty else { throw ChapterError.unsupported }
        let link: JSONValue = .object(["type": .string("entryLink"), "attrs": .object(["entryId": .string(target.id), "label": .string(EntryLinkAuthoring.label(for: target))])])
        return try editingRichDocument(expected: expected, now: now) { try $0.insertInline([link, .object(["type": .string("text"), "text": .string(" ")])], at: caret) }
    }
    /// Original toolbar formatting applied to a selection inside one text leaf.
    func togglingMark(_ type: String, leaf: [Int], utf16Range: Range<Int>, expected: String, now: Date = Date()) throws -> VaultRecord {
        try editingRichDocument(expected: expected, now: now) { try $0.toggleMark(type, leaf: leaf, utf16Range: utf16Range) }
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
