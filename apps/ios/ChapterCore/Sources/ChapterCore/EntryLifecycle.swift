// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

public extension VaultSnapshot {
    /// Tombstone and local recovery checkpoint are committed together. Never
    /// erase an upload queue, rich draft or pending writing to implement Delete.
    mutating func deleteEntryPreservingRecovery(expected: VaultRecord, now: Date = Date()) throws {
        guard let index = records.firstIndex(where: { $0.id == expected.id }),
              records[index].kind == "entry", !records[index].deleted else { throw ChapterError.conflict }
        let original = records[index]
        try original.requiringUnchanged(expected: expected)
        let clock = try ProtocolNumbers.nextClock(after: original.clock, now: now)
        var next = self
        if !next.conflicts.contains(where: { $0.hasSameVersion(as: original) }) {
            next.conflicts.append(original)
        }
        next.records[index].clock = clock; next.records[index].deleted = true; next.records[index].dirty = true
        next.records[index].body["updatedAt"] = .number(Double(clock))
        self = next
    }
}
