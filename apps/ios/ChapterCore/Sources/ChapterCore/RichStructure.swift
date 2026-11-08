// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

extension VaultSnapshot {
    /// Caller advances its displayed checkpoint ONLY after encrypted save succeeds.
    /// Pending drafts retain their original document/path; never silently rebase.
    @discardableResult public mutating func reorderRichBlocks(expected: VaultRecord, from offsets: IndexSet, to destination: Int, now: Date = Date()) throws -> VaultRecord {
        guard records.filter({ $0.id == expected.id }).count == 1,
              let index = records.firstIndex(where: { $0.id == expected.id }),
              records[index].kind == "entry", !records[index].deleted,
              let raw = records[index].body["bodyJson"]?.string else { throw ChapterError.conflict }
        try records[index].requiringUnchanged(expected: expected)
        var document = try RichDocument(json: raw)
        guard try document.moveBlocks(from: offsets, to: destination) else { return records[index] }
        let updated = try records[index].editingRichDocument(expected: raw, now: now) { $0 = document }
        records[index] = updated; return updated
    }
}
