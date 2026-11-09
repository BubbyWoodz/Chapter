// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

public enum EntryLabels {
    // ECMAScript label identity is code-unit exact. Swift String equality is
    // canonically equivalent and would conflate imported NFC/NFD labels.
    public static func contains(_ labels: [String], _ candidate: String) -> Bool {
        labels.contains { $0.utf8.elementsEqual(candidate.utf8) }
    }
    public static func sameValues(_ lhs: [String], _ rhs: [String]) -> Bool {
        lhs.count == rhs.count && zip(lhs,rhs).allSatisfy { $0.utf8.elementsEqual($1.utf8) }
    }
    public static func unique(_ labels: [String]) -> [String] {
        var seen = Set<Data>()
        return labels.filter { seen.insert(Data($0.utf8)).inserted }
    }
    /// Older native plain forms used a comma field. An unrelated text/title
    /// save must NEVER split an imported literal-comma label or erase future
    /// label schemas. New/explicit comma input uses original web normalization.
    public static func plainFieldValue(_ input: String, original: VaultRecord?) throws -> JSONValue? {
        if let original {
            if input.utf8.elementsEqual(original.labels.joined(separator:", ").utf8) { return original.body["labels"] }
            guard original.editableEntryLabels != nil else { throw ChapterError.unsupported }
        }
        return .array(unique(input.split(separator:",").map { normalized(String($0)) }.filter { !$0.isEmpty }).map(JSONValue.string))
    }
    /// Original LabelField: trim().toLowerCase().replace(/\s+/g, ' ').
    public static func normalized(_ raw: String) -> String {
        let whitespace = CharacterSet(charactersIn: "\u{0009}\u{000A}\u{000B}\u{000C}\u{000D}\u{0020}\u{00A0}\u{1680}\u{2000}\u{2001}\u{2002}\u{2003}\u{2004}\u{2005}\u{2006}\u{2007}\u{2008}\u{2009}\u{200A}\u{2028}\u{2029}\u{202F}\u{205F}\u{3000}\u{FEFF}")
        // Whole-string root-locale Unicode casing, like ECMAScript. Swift's
        // locale-free scalar casing differs for contextual Greek final sigma.
        return raw.lowercased(with: Locale(identifier: "und")).components(separatedBy: whitespace).filter { !$0.isEmpty }.joined(separator: " ")
    }
}
public extension VaultRecord {
    /// Unknown label schemas stay opaque. Title/date edits must not erase them.
    var editableEntryLabels: [String]? {
        guard let value = body["labels"] else { return [] }
        guard case .array(let labels) = value else { return nil }
        var result: [String] = []
        for label in labels { guard case .string(let text) = label else { return nil }; result.append(text) }
        return result
    }
    func editingEntryMetadata(expected: VaultRecord, title: String? = nil, date: Date? = nil, labels: [String]? = nil, now: Date = Date()) throws -> VaultRecord {
        guard kind == "entry", !deleted else { throw ChapterError.unsupported }
        try requiringUnchanged(expected: expected)
        var next = self, changed = false
        if let title {
            guard title.utf8.count <= 8 * 1024 * 1024 else { throw ChapterError.unsupported }
            if let original = body["title"]?.string, original.utf8.elementsEqual(title.utf8) {} else { next.body["title"] = .string(title); changed = true }
        }
        if let date {
            let milliseconds = date.timeIntervalSince1970 * 1000
            guard milliseconds.isFinite, (-62_135_596_800_000...253_402_300_799_999).contains(milliseconds) else { throw ChapterError.invalidClock }
            if body["createdAt"] != .number(milliseconds) { next.body["createdAt"] = .number(milliseconds); changed = true }
        }
        if let labels {
            guard editableEntryLabels != nil, labels.allSatisfy({ $0.utf8.count <= 8 * 1024 * 1024 }) else { throw ChapterError.unsupported }
            if body["labels"] == nil || !EntryLabels.sameValues(editableEntryLabels ?? [],labels) {
                next.body["labels"] = .array(labels.map(JSONValue.string)); changed = true
            }
        }
        guard changed else { return self }
        next.clock = try ProtocolNumbers.nextClock(after: clock, now: now)
        next.body["updatedAt"] = .number(Double(next.clock)); next.dirty = true
        return next
    }
}
