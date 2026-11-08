// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

public enum EntryLabels {
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
        var next = self
        if let title { guard title.utf8.count <= 8 * 1024 * 1024 else { throw ChapterError.unsupported }; next.body["title"] = .string(title) }
        if let date {
            let milliseconds = date.timeIntervalSince1970 * 1000
            guard milliseconds.isFinite, (-62_135_596_800_000...253_402_300_799_999).contains(milliseconds) else { throw ChapterError.invalidClock }
            next.body["createdAt"] = .number(milliseconds)
        }
        if let labels {
            guard editableEntryLabels != nil, labels.allSatisfy({ $0.utf8.count <= 8 * 1024 * 1024 }) else { throw ChapterError.unsupported }
            next.body["labels"] = .array(labels.map(JSONValue.string))
        }
        guard next.body != body else { return self }
        next.clock = try ProtocolNumbers.nextClock(after: clock, now: now)
        next.body["updatedAt"] = .number(Double(next.clock)); next.dirty = true
        return next
    }
}
