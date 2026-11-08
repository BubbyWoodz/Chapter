// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

// Swift String equality is canonically equivalent; a same-clock NFC/NFD edit
// must NOT count as an unchanged original journal. Compare stable encoded bytes
// too, ignoring only delivery acknowledgement when checking record checkpoints.
private func notebookRecordMatches(_ lhs:VaultRecord,_ rhs:VaultRecord,ignoringAcknowledgement:Bool = false) throws -> Bool {
    var left=lhs,right=rhs
    if ignoringAcknowledgement {left.dirty=false;right.dirty=false}
    let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
    return try encoder.encode(left) == encoder.encode(right)
}
private func requireNotebookCheckpoint(_ current:VaultRecord,_ expected:VaultRecord) throws {
    try current.requiringUnchanged(expected:expected)
    guard try notebookRecordMatches(current,expected,ignoringAcknowledgement:true) else {throw ChapterError.conflict}
}

/// Frozen LOCAL downloaded-set intent. The original relay has no atomic
/// notebook-delete transaction or cross-client fence; unseen/concurrent remote
/// entries are not claimed deleted. Pending writing/media are never removed.
public struct NotebookDeletionPlan: Codable, Equatable, Identifiable {
    public let id: String
    public let notebook: VaultRecord
    public let entries: [VaultRecord]
    public init(snapshot: VaultSnapshot, notebook: VaultRecord) throws {
        guard notebook.kind == "journal", !notebook.deleted, !notebook.journalID.isEmpty,
              snapshot.records.filter({$0.id == notebook.id}).count == 1,
              snapshot.records.filter({$0.kind == "journal" && !$0.deleted && $0.journalID == notebook.journalID}).count == 1 else { throw ChapterError.conflict }
        guard let current = snapshot.records.first(where:{$0.id == notebook.id}) else { throw ChapterError.conflict }
        try requireNotebookCheckpoint(current,notebook)
        id = "local-notebook-deletion-" + UUID().uuidString.lowercased()
        self.notebook = current
        entries = snapshot.records.filter {$0.kind == "entry" && !$0.deleted && $0.journalID == notebook.journalID}.sorted {$0.id < $1.id}
        try validate()
    }
    public func validate() throws {
        let originals = [notebook] + entries
        guard id.hasPrefix("local-notebook-deletion-"), notebook.kind == "journal", !notebook.deleted,
              !notebook.journalID.isEmpty, entries.count < 10_000,
              Set(originals.map(\.id)).count == originals.count,
              entries.allSatisfy({$0.kind == "entry" && !$0.deleted && $0.journalID == notebook.journalID}),
              originals.allSatisfy({!$0.id.isEmpty}),
              try JSONEncoder().encode(originals).count <= 64 * 1024 * 1024 else { throw ChapterError.unsupported }
        for original in originals { try ProtocolNumbers.validate(original.clock) }
    }
}

/// Immutable original bodies plus tombstone clocks, not duplicate rich bodies.
/// Stored ONLY as an opaque local encrypted conflict, never as a relay record.
public struct NotebookDeletionRecovery: Codable, Equatable {
    public static let recoveryKind = "chapterLocalNotebookDeletion"
    public let plan: NotebookDeletionPlan
    public let clocks: [Int64]
    public var restored: Bool
    public init(plan: NotebookDeletionPlan, now: Date = Date()) throws {
        try plan.validate(); self.plan = plan
        clocks = try ([plan.notebook] + plan.entries).map {try ProtocolNumbers.nextClock(after:$0.clock,now:now)}
        restored = false
    }
    public func tombstones() throws -> [VaultRecord] {
        try plan.validate()
        let originals = [plan.notebook] + plan.entries
        guard clocks.count == originals.count else { throw ChapterError.corruptData }
        return try zip(originals,clocks).map { original,clock in
            try ProtocolNumbers.validate(clock); guard clock > original.clock else { throw ChapterError.corruptData }
            var record = original; record.clock = clock; record.deleted = true; record.dirty = true
            record.body["updatedAt"] = .number(Double(clock)); return record
        }
    }
    public func recoveryRecord() throws -> VaultRecord {
        _ = try tombstones()
        let payload = try JSONDecoder().decode(JSONValue.self,from:JSONEncoder().encode(self))
        return VaultRecord(id:plan.id,clock:1,body:["kind":.string(Self.recoveryKind),"title":.string("Notebook recovery: " + plan.notebook.title),"bodyText":.string("Retains " + String(plan.entries.count) + " downloaded entries and the original notebook. Encrypted media and writing drafts are retained; not secure erasure."),"localNotebookDeletion":payload])
    }
    public init(recovery: VaultRecord) throws {
        guard recovery.kind == Self.recoveryKind, !recovery.deleted, let payload = recovery.body["localNotebookDeletion"] else { throw ChapterError.corruptData }
        self = try JSONDecoder().decode(Self.self,from:JSONEncoder().encode(payload))
        guard try notebookRecordMatches(recoveryRecord(),recovery) else { throw ChapterError.corruptData }
    }
}

public extension VaultSnapshot {
    mutating func deleteNotebookPreservingRecovery(_ plan: NotebookDeletionPlan, now: Date = Date()) throws {
        try plan.validate()
        guard conflicts.filter({$0.kind == NotebookDeletionRecovery.recoveryKind}).count < 128,
              !conflicts.contains(where:{$0.id == plan.id}),
              records.filter({$0.kind == "journal" && !$0.deleted && $0.journalID == plan.notebook.journalID}).count == 1 else { throw ChapterError.conflict }
        let currentEntries = records.filter {$0.kind == "entry" && !$0.deleted && $0.journalID == plan.notebook.journalID}
        guard Set(currentEntries.map(\.id)) == Set(plan.entries.map(\.id)), currentEntries.count == plan.entries.count else { throw ChapterError.conflict }
        let recovery = try NotebookDeletionRecovery(plan:plan,now:now)
        let originals = [plan.notebook] + plan.entries, tombstones = try recovery.tombstones()
        var next = self
        for (original,tombstone) in zip(originals,tombstones) {
            guard next.records.filter({$0.id == original.id}).count == 1,
                  let index = next.records.firstIndex(where:{$0.id == original.id}) else { throw ChapterError.conflict }
            try requireNotebookCheckpoint(next.records[index],original)
            next.records[index] = tombstone
        }
        next.conflicts.append(try recovery.recoveryRecord())
        self = next // Caller commits checkpoint + ALL tombstones in one encrypted save.
    }
    mutating func restoreNotebookDeletion(_ expected: VaultRecord, now: Date = Date()) throws {
        var recovery = try NotebookDeletionRecovery(recovery:expected)
        guard !recovery.restored, let recoveryIndex = conflicts.firstIndex(where:{$0.id == expected.id}),
              try notebookRecordMatches(conflicts[recoveryIndex],expected),
              !records.contains(where:{$0.kind == "journal" && !$0.deleted && $0.journalID == recovery.plan.notebook.journalID}) else { throw ChapterError.conflict }
        let originals = [recovery.plan.notebook] + recovery.plan.entries, tombstones = try recovery.tombstones()
        var next = self
        for (original,tombstone) in zip(originals,tombstones) {
            guard next.records.filter({$0.id == original.id}).count == 1,
                  let index = next.records.firstIndex(where:{$0.id == original.id}) else { throw ChapterError.conflict }
            try requireNotebookCheckpoint(next.records[index],tombstone)
            var restored = original; restored.clock = try ProtocolNumbers.nextClock(after:tombstone.clock,now:now)
            restored.deleted = false; restored.dirty = true; restored.body["updatedAt"] = .number(Double(restored.clock))
            next.records[index] = restored
        }
        recovery.restored = true; next.conflicts[recoveryIndex] = try recovery.recoveryRecord()
        self = next // Keep historical encrypted recovery; restoring is also atomic.
    }
}
