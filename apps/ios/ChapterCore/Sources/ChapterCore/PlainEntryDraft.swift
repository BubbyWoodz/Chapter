// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

/// Local-only writing recovery. Stored inside existing opaque recovery records,
/// never the synced records array. Older native snapshots retain this dictionary
/// unchanged, but cannot resume it. No vault/server format or key change.
public struct PlainEntryDraft: Codable, Equatable, Identifiable {
    public static let recoveryKind = "chapterLocalWritingDraft"
    public let id: String
    public var revision: Int64
    public var expected: VaultRecord?
    public var title: String
    public var text: String
    public var labels: String
    public var date: Date
    public var journal: String
    public init(existing: VaultRecord? = nil, journal: String) {
        id = "local-writing-" + UUID().uuidString.lowercased(); revision = 0
        expected = existing; title = existing?.title ?? ""; text = existing?.text ?? ""
        labels = existing?.labels.joined(separator: ", ") ?? ""
        date = existing?.date ?? Date(); self.journal = journal
    }
    public func validate() throws {
        guard id.hasPrefix("local-writing-"), !journal.isEmpty,
              revision >= 0, revision <= ProtocolNumbers.maxWireInteger,
              (date.timeIntervalSince1970 * 1000).isFinite,
              title.utf8.count <= 8 * 1024 * 1024,
              text.utf8.count <= 8 * 1024 * 1024,
              labels.utf8.count <= 8 * 1024 * 1024 else { throw ChapterError.unsupported }
        if let expected {
            guard expected.kind == "entry", !expected.deleted, expected.editablePlainText else { throw ChapterError.unsupported }
        }
    }
    public func separateRecovery() -> PlainEntryDraft {
        var separate = Self(existing: expected, journal: journal)
        separate.title = title; separate.text = text; separate.labels = labels; separate.date = date
        return separate
    }
    public func recoveryRecord() throws -> VaultRecord {
        try validate(); guard revision > 0 else { throw ChapterError.corruptData }
        let payload = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(self))
        return VaultRecord(id: id, clock: revision, body: ["kind": .string(Self.recoveryKind), "title": .string(title.isEmpty ? "Unsaved writing" : title), "bodyText": .string(text), "localDraft": payload])
    }
    public init(recovery: VaultRecord) throws {
        guard recovery.kind == Self.recoveryKind, !recovery.deleted, let payload = recovery.body["localDraft"] else { throw ChapterError.corruptData }
        self = try JSONDecoder().decode(Self.self, from: JSONEncoder().encode(payload))
        try validate()
        guard revision > 0, recovery.id == id, recovery.clock == revision,
              try recoveryRecord() == recovery else { throw ChapterError.corruptData }
    }
}

public extension VaultSnapshot {
    /// CAS protects a resumed draft from a second stale editor. No eviction.
    mutating func keepPlainDraft(_ draft: PlainEntryDraft) throws -> PlainEntryDraft {
        try draft.validate()
        let index = conflicts.firstIndex { $0.id == draft.id }
        if let index {
            let stored = try PlainEntryDraft(recovery: conflicts[index])
            guard stored.revision == draft.revision else { throw ChapterError.conflict }
        } else {
            guard draft.revision == 0 else { throw ChapterError.conflict }
            guard conflicts.filter({ $0.kind == PlainEntryDraft.recoveryKind }).count < 256 else { throw ChapterError.unsupported }
        }
        var saved = draft
        saved.revision = try ProtocolNumbers.nextClock(after: draft.revision, now: Date(timeIntervalSince1970: 0))
        let record = try saved.recoveryRecord()
        if let index { conflicts[index] = record } else { conflicts.append(record) }
        return saved
    }
    /// Remove only the exact durable revision as part of an entry's atomic save.
    mutating func finishPlainDraft(_ draft: PlainEntryDraft) throws {
        let expected = try draft.recoveryRecord()
        guard let index = conflicts.firstIndex(where: { $0.id == draft.id }), conflicts[index] == expected else { throw ChapterError.conflict }
        conflicts.remove(at: index)
    }
}
