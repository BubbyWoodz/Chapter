// SPDX-License-Identifier: AGPL-3.0-or-later
import XCTest
import CryptoKit
@testable import ChapterCore

final class EntryLifecycleTests: XCTestCase {
    private func snapshot() throws -> VaultSnapshot {
        var value = VaultSnapshot()
        let original = VaultRecord(id: "public-offline-entry", clock: 12, body: ["title": .string("Offline writing"), "bodyText": .string("Not uploaded yet"), "bodyJson": .string(try VaultRecord.plainDocument("Not uploaded yet")), "chapterNativePlain": .bool(true), "opaque": .object(["keep":.bool(true)])], dirty: true)
        value.records = [original]
        value.richDrafts = [RichDraft(entryID: original.id, path: [0,0], expectedDocument: original.body["bodyJson"]!.string!, text: "Pending rich text")]
        var writing = PlainEntryDraft(existing: original, journal: "default"); writing.text = "Pending plain text"
        _ = try value.keepPlainDraft(writing)
        value.mediaUploads = [MediaUpload(id: String(repeating:"a",count:32), chunks:1, cipherBytes:42, plainBytes:1, name:"Public pending file", mime:"application/octet-stream")]
        value.mediaCache = [MediaCache(id:String(repeating:"a",count:32), chunks:1, cipherBytes:42)]
        return value
    }
    func testOfflineDeletePreservesAllPendingWorkAndOriginalRecovery() throws {
        var value = try snapshot(); let original = value.records[0]; let before = value
        try value.deleteEntryPreservingRecovery(expected: original, now: Date(timeIntervalSince1970:100))
        XCTAssertTrue(value.records[0].deleted); XCTAssertTrue(value.records[0].dirty)
        XCTAssertEqual(value.records[0].clock,100000)
        XCTAssertEqual(value.mediaUploads,before.mediaUploads); XCTAssertEqual(value.mediaCache,before.mediaCache)
        XCTAssertEqual(value.richDrafts,before.richDrafts)
        XCTAssertEqual(value.conflicts.first, before.conflicts.first)
        XCTAssertEqual(value.conflicts.last, original)
        let restored = try XCTUnwrap(value.conflicts.last).restoredEntry(id:"new-public-recovery", now:Date(timeIntervalSince1970:101))
        XCTAssertFalse(restored.deleted); XCTAssertTrue(restored.dirty)
        XCTAssertEqual(restored.body["bodyJson"],original.body["bodyJson"]); XCTAssertEqual(restored.body["opaque"],original.body["opaque"])
    }
    func testStaleDeletedAndOverflowDeleteLeaveEntireSnapshotUnchanged() throws {
        let original = try snapshot(); var changed = original; changed.records[0].clock += 1
        let before = changed; XCTAssertThrowsError(try changed.deleteEntryPreservingRecovery(expected:original.records[0])); XCTAssertEqual(changed,before)
        changed = original; changed.records[0].deleted = true; let deleted = changed
        XCTAssertThrowsError(try changed.deleteEntryPreservingRecovery(expected:changed.records[0])); XCTAssertEqual(changed,deleted)
        changed = original; changed.records[0].clock = ProtocolNumbers.maxWireInteger; let overflow = changed
        XCTAssertThrowsError(try changed.deleteEntryPreservingRecovery(expected:changed.records[0])); XCTAssertEqual(changed,overflow)
        changed = original; changed.conflicts.append(original.records[0]); var acknowledged = original.records[0]; acknowledged.dirty = false; changed.records[0] = acknowledged
        try changed.deleteEntryPreservingRecovery(expected: original.records[0])
        XCTAssertEqual(changed.conflicts.filter { $0.id == acknowledged.id }.count,1)
    }
    func testEncryptedDeleteFailureRetainsOriginalThenRetryKeepsRecovery() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:folder) }
        let store = EncryptedSnapshotStore(directory:folder,namespace:"public-offline-delete",key:SymmetricKey(data:Data(repeating:21,count:32)))
        let before = try snapshot(); try store.save(before)
        var next = before; try next.deleteEntryPreservingRecovery(expected:before.records[0])
        store.prepareWriteForTesting = { throw NSError(domain:"public-disk-failure",code:1) }
        XCTAssertThrowsError(try store.save(next)); XCTAssertEqual(try store.load(),before)
        store.prepareWriteForTesting = nil; try store.save(next)
        XCTAssertEqual(try store.load(),next)
        XCTAssertEqual(try store.load().conflicts.last,before.records[0])
    }
}
