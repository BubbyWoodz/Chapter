// SPDX-License-Identifier: AGPL-3.0-or-later
import XCTest
import CryptoKit
@testable import ChapterCore

final class PlainEntryDraftTests: XCTestCase {
    private func entry() throws -> VaultRecord {
        VaultRecord(id: "public-plain-source", clock: 12, body: ["title": .string("Original"), "bodyText": .string("Original text"), "bodyJson": .string(try VaultRecord.plainDocument("Original text")), "chapterNativePlain": .bool(true), "journalId": .string("public-notebook"), "opaque": .array([.bool(true), .number(7)])])
    }
    func testLocalRecoveryCASFinishAndOldSnapshotRoundtripNeverPublishOrDiscard() throws {
        let original = try entry(); var snapshot = VaultSnapshot(); snapshot.records = [original]
        let other = VaultRecord(id: "other-conflict", clock: 2, body: ["title": .string("Keep me")])
        snapshot.conflicts = [other]
        var draft = PlainEntryDraft(existing: original, journal: original.journalID)
        draft.text = "PRIVATE-RECOVERY-WRITING"; draft.labels = "a, b"
        let stale = draft; draft = try snapshot.keepPlainDraft(draft)
        XCTAssertEqual(draft.revision, 1); XCTAssertEqual(snapshot.records, [original])
        let first = snapshot
        XCTAssertThrowsError(try snapshot.keepPlainDraft(stale)); XCTAssertEqual(snapshot, first)
        let oldRevision = draft; draft.text += " more"; draft = try snapshot.keepPlainDraft(draft)
        let second = snapshot
        XCTAssertThrowsError(try snapshot.finishPlainDraft(oldRevision)); XCTAssertEqual(snapshot, second)
        var remote = original; remote.clock += 1; remote.body["bodyText"] = .string("Other client text")
        XCTAssertThrowsError(try remote.requiringUnchanged(expected: XCTUnwrap(draft.expected)))
        XCTAssertEqual(try PlainEntryDraft(recovery: XCTUnwrap(snapshot.conflicts.first { $0.id == draft.id })), draft)
        struct OldSnapshotV4: Codable {
            var version: Int; var records: [VaultRecord]; var cursor: Int64; var conflicts: [VaultRecord]
            var mediaUploads: [MediaUpload]?; var mediaCache: [MediaCache]?; var richDrafts: [RichDraft]?
        }
        let old = try JSONDecoder().decode(OldSnapshotV4.self, from: JSONEncoder().encode(snapshot))
        let reopened = try JSONDecoder().decode(VaultSnapshot.self, from: JSONEncoder().encode(old))
        XCTAssertEqual(reopened, snapshot, "Old v4 opaque recovery dictionaries preserve every new field")
        try snapshot.finishPlainDraft(draft)
        XCTAssertEqual(snapshot.conflicts, [other]); XCTAssertEqual(snapshot.records, [original])
        XCTAssertEqual(snapshot.uploadableRecords, [])
        let separate = draft.separateRecovery()
        XCTAssertNotEqual(separate.id, draft.id); XCTAssertEqual(separate.revision, 0)
        XCTAssertEqual(separate.text, draft.text); XCTAssertEqual(separate.expected, draft.expected)
    }
    func testInvalidRecoveryAndCapacityFailClosedWithoutEviction() throws {
        var snapshot = VaultSnapshot(); var draft = PlainEntryDraft(journal: "default")
        for _ in 0..<256 { _ = try snapshot.keepPlainDraft(PlainEntryDraft(journal: "default")) }
        let full = snapshot
        XCTAssertThrowsError(try snapshot.keepPlainDraft(draft)); XCTAssertEqual(snapshot, full)
        var existing = try PlainEntryDraft(recovery: snapshot.conflicts[0]); existing.text = "Still editable at capacity"
        XCTAssertNoThrow(try snapshot.keepPlainDraft(existing)); XCTAssertEqual(snapshot.conflicts.count, 256)
        draft.date = Date(timeIntervalSince1970: .infinity); XCTAssertThrowsError(try draft.validate())
        var malformed = snapshot.conflicts[0]; malformed.clock += 1
        XCTAssertThrowsError(try PlainEntryDraft(recovery: malformed))
        var notPlain = try entry(); notPlain.body["kind"] = .string("template")
        XCTAssertThrowsError(try PlainEntryDraft(existing: notPlain, journal: "default").validate())
        let overflowPayload: [String:JSONValue] = ["id":.string("local-writing-overflow"),"revision":.number(Double(ProtocolNumbers.maxWireInteger)),"title":.string(""),"text":.string(""),"labels":.string(""),"date":.number(0),"journal":.string("default")]
        let overflow = try JSONDecoder().decode(PlainEntryDraft.self, from: JSONEncoder().encode(overflowPayload))
        var limit = VaultSnapshot(); limit.conflicts = [try overflow.recoveryRecord()]; let before = limit
        XCTAssertThrowsError(try limit.keepPlainDraft(overflow)); XCTAssertEqual(limit, before)
    }
    func testActualEncryptedRestartWriteFailureAndRetryKeepWriting() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let key = SymmetricKey(data: Data(repeating: 17, count: 32))
        let store = EncryptedSnapshotStore(directory: folder, namespace: "public-writing-recovery", key: key)
        var snapshot = VaultSnapshot(); var draft = PlainEntryDraft(existing: try entry(), journal: "public-notebook")
        draft.text = "PRIVATE-RECOVERY-WRITING"; draft = try snapshot.keepPlainDraft(draft)
        try store.save(snapshot)
        let file = folder.appendingPathComponent("public-writing-recovery.vault")
        let oldBytes = try Data(contentsOf: file); XCTAssertNil(oldBytes.range(of: Data(draft.text.utf8)))
        XCTAssertEqual(try store.load(), snapshot)
        var next = snapshot; draft.text += " additional"; let newer = try next.keepPlainDraft(draft)
        store.prepareWriteForTesting = { throw NSError(domain: "public-disk-failure", code: 1) }
        XCTAssertThrowsError(try store.save(next)); XCTAssertEqual(try Data(contentsOf: file), oldBytes)
        let reopened = try store.load()
        XCTAssertEqual(try PlainEntryDraft(recovery: XCTUnwrap(reopened.conflicts.first)), try PlainEntryDraft(recovery: XCTUnwrap(snapshot.conflicts.first)))
        store.prepareWriteForTesting = nil; try store.save(next)
        XCTAssertEqual(try PlainEntryDraft(recovery: XCTUnwrap(store.load().conflicts.first)), newer)
        let wrongKey = EncryptedSnapshotStore(directory: folder, namespace: "public-writing-recovery", key: SymmetricKey(data: Data(repeating: 18, count: 32)))
        XCTAssertThrowsError(try wrongKey.load()); XCTAssertEqual(try store.load(), next)
    }
}
