import Foundation

/// Formatting a selection that spans several runs of one textblock, as the
/// original toolbar's TipTap toggleMark does it over a ProseMirror range.
/// Positions are block-relative ProseMirror positions: text counts UTF-16 code
/// units and every other inline node (entry link, math, hard break) counts 1.
/// Verified against the real TipTap Editor (rich-range-format.json).
public extension RichDocument {
    /// The block's inline content as one string, each non-text inline node shown
    /// as U+FFFC so UTF-16 offsets equal ProseMirror positions.
    func formattingText(block path: [Int]) throws -> String {
        guard let block = nodeValue(at: path), Self.textblockTypes.contains(block["type"].string ?? "") else { throw ChapterError.unsupported }
        return block["content"].array.map { $0["type"].string == "text" ? ($0["text"].string ?? "") : "\u{FFFC}" }.joined()
    }

    /// Paragraphs and headings with inline content, reached only through known containers.
    var formattableBlocks: [[Int]] {
        var found: [[Int]] = []
        func walk(_ node: JSONValue, _ path: [Int]) {
            for (i, child) in node["content"].array.enumerated() {
                let type = child["type"].string ?? ""
                if type == "paragraph" || type == "heading" { if !child["content"].array.isEmpty { found.append(path + [i]) } }
                else if Self.containers.contains(type) { walk(child, path + [i]) }
            }
        }
        walk(root, []); return found
    }

    mutating func toggleMark(_ type: String, block path: [Int], range: Range<Int>) throws {
        guard Self.editableMarks.contains(type), !range.isEmpty, range.lowerBound >= 0,
              let blockValue = nodeValue(at: path), case .object(var block) = blockValue,
              Self.textblockTypes.contains(block["type"]?.string ?? ""), block["type"]?.string != "codeBlock" else { throw ChapterError.unsupported }
        let content = blockValue["content"].array, name: (JSONValue) -> String = { $0["type"].string ?? "" }
        var starts: [Int] = [], position = 0
        for node in content { starts.append(position); position += node["type"].string == "text" ? (node["text"].string ?? "").utf16.count : 1 }
        guard range.upperBound <= position else { throw ChapterError.unsupported }
        func size(_ i: Int) -> Int { (i + 1 < starts.count ? starts[i + 1] : position) - starts[i] }
        let overlapping = content.indices.filter { starts[$0] < range.upperBound && starts[$0] + size($0) > range.lowerBound }
        // Selection ends must not split a surrogate pair inside a text node.
        for i in overlapping where content[i]["type"].string == "text" {
            let text = content[i]["text"].string ?? "", utf16 = text.utf16
            for bound in [range.lowerBound, range.upperBound] where bound > starts[i] && bound < starts[i] + size(i) {
                guard utf16.index(utf16.startIndex, offsetBy: bound - starts[i]).samePosition(in: text.unicodeScalars) != nil else { throw ChapterError.unsupported }
            }
        }
        func marks(_ node: JSONValue) -> [JSONValue] { node["marks"].array }
        func has(_ node: JSONValue, _ t: String) -> Bool { marks(node).contains { name($0) == t } }
        func excludes(_ a: String, _ b: String) -> Bool { a == b || Self.markExclusions[a]?.contains(b) == true }
        // TipTap isMarkActive over a range: covered text plus text whose marks exclude this mark.
        var selectionRange = 0, matched = 0, excluded = 0
        for i in overlapping {
            let node = content[i]
            guard node["type"].string == "text" || !marks(node).isEmpty else { continue }
            let span = min(range.upperBound, starts[i] + size(i)) - max(range.lowerBound, starts[i])
            selectionRange += span
            for mark in marks(node) {
                if name(mark) == type { matched += span } else if excludes(name(mark), type) { excluded += span }
            }
        }
        let active = selectionRange > 0 && (matched > 0 ? matched + excluded : 0) >= selectionRange
        var changed: [Int: [JSONValue]] = [:]
        if active {
            for i in overlapping where has(content[i], type) { changed[i] = marks(content[i]).filter { name($0) != type } }
        } else {
            // TipTap canSetMark: some inline node already has the mark or is not excluded from it.
            guard overlapping.contains(where: { has(content[$0], type) || !marks(content[$0]).contains { excludes(name($0), type) } }) else { throw ChapterError.unsupported }
            let removes = Self.markExclusions[type] ?? []
            for i in overlapping where !has(content[i], type) && !marks(content[i]).contains(where: { excludes(name($0), type) }) {
                // Adding code would erase links or marks unknown to this build; never silently.
                guard !marks(content[i]).contains(where: { removes.contains(name($0)) && !Self.editableMarks.contains(name($0)) }) else { throw ChapterError.unsupported }
                changed[i] = Self.insertingMark(.object(["type": .string(type)]), into: marks(content[i]).filter { !removes.contains(name($0)) })
            }
        }
        guard !changed.isEmpty else { throw ChapterError.unsupported }
        func with(_ node: JSONValue, marks: [JSONValue]) -> JSONValue {
            guard case .object(var fields) = node else { return node }
            if marks.isEmpty { fields.removeValue(forKey: "marks") } else { fields["marks"] = .array(marks) }
            return .object(fields)
        }
        var next: [JSONValue] = []
        for (i, node) in content.enumerated() {
            guard let newMarks = changed[i] else { next.append(node); continue }
            guard node["type"].string == "text", case .object(let fields) = node, let text = fields["text"]?.string else { next.append(with(node, marks: newMarks)); continue }
            let utf16 = text.utf16, lo = max(range.lowerBound - starts[i], 0), hi = min(range.upperBound - starts[i], utf16.count)
            func part(_ a: Int, _ b: Int) -> String { String(utf16[utf16.index(utf16.startIndex, offsetBy: a)..<utf16.index(utf16.startIndex, offsetBy: b)])! }
            func piece(_ s: String, _ m: [JSONValue]?) -> JSONValue { var copy = fields; copy["text"] = .string(s); return m.map { with(.object(copy), marks: $0) } ?? .object(copy) }
            if lo > 0 { next.append(piece(part(0, lo), nil)) }
            next.append(piece(part(lo, hi), newMarks))
            if hi < utf16.count { next.append(piece(part(hi, utf16.count), nil)) }
        }
        // ProseMirror Fragment.fromArray joins adjacent equal-mark text; the left node's fields win.
        var joined: [JSONValue] = []
        for node in next {
            if let last = joined.last, let merged = Self.join(last, node, keepFirst: true) { joined[joined.count - 1] = merged } else { joined.append(node) }
        }
        block["content"] = .array(joined)
        try replacing(path, with: [.object(block)])
    }
}

public extension VaultRecord {
    /// Original toolbar formatting applied to a selection across a textblock's runs.
    func togglingMark(_ type: String, block: [Int], range: Range<Int>, expected: String, now: Date = Date()) throws -> VaultRecord {
        try editingRichDocument(expected: expected, now: now) { try $0.toggleMark(type, block: block, range: range) }
    }
}
