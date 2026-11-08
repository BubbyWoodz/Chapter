// SPDX-License-Identifier: AGPL-3.0-or-later
import XCTest
import CryptoKit
@testable import ChapterCore

final class NotebookLifecycleTests: XCTestCase {
    private let mediaID = String(repeating:"a",count:32)
    private func snapshot() throws -> VaultSnapshot {
        var value = VaultSnapshot()
        let fixture = try JSONDecoder().decode([String:JSONValue].self,from:Data(contentsOf:XCTUnwrap(Bundle.module.url(forResource:"rich-document",withExtension:"json"))))
        let document = String(decoding:try JSONEncoder().encode(fixture["original"]!),as:UTF8.self)
        value.records = [
            VaultRecord(id:"notebook-original",clock:12,body:["kind":.string("journal"),"journalId":.string("original"),"name":.string("Original notebook"),"cover":.string("lines"),"opaqueFuture":.object(["keep":.bool(true)])],dirty:true),
            VaultRecord(id:"entry-original",clock:13,body:["journalId":.string("original"),"title":.string("Original rich entry"),"bodyJson":.string(document),"bodyText":fixture["originalPreview"]!,"labels":.array([.string("travel, friends")]),"attachments":.array([.object(["id":.string(mediaID),"name":.string("Pending public photo"),"mime":.string("image/png"),"bytes":.number(1)])]),"opaqueFuture":.object(["keep":.bool(true)])],dirty:true),
            VaultRecord(id:"unrelated",clock:14,body:["journalId":.string("other"),"title":.string("Unrelated entry")],dirty:true)]
        value.richDrafts = [RichDraft(entryID:"entry-original",path:[0,0],expectedDocument:document,text:"Pending native writing")]
        value.mediaUploads = [MediaUpload(id:mediaID,chunks:1,cipherBytes:42,plainBytes:1,name:"Pending public photo",mime:"image/png")]
        value.mediaCache = [MediaCache(id:mediaID,chunks:1,cipherBytes:42)]
        _ = try value.keepPlainDraft(PlainEntryDraft(journal:"original"))
        return value
    }
    func testOfflineCascadeAndRestorePreserveOriginalsQueuesDraftsAndUnknownFields() throws {
        var value = try snapshot(); let before = value
        let plan = try NotebookDeletionPlan(snapshot:value,notebook:value.records[0])
        try value.deleteNotebookPreservingRecovery(plan,now:Date(timeIntervalSince1970:100))
        XCTAssertTrue(value.records[0].deleted); XCTAssertTrue(value.records[1].deleted)
        XCTAssertEqual(value.records[2],before.records[2]); XCTAssertEqual(value.richDrafts,before.richDrafts)
        XCTAssertEqual(value.mediaUploads,before.mediaUploads); XCTAssertEqual(value.mediaCache,before.mediaCache)
        XCTAssertEqual(value.conflicts.first,before.conflicts.first)
        let capsule = try XCTUnwrap(value.conflicts.last), recovery = try NotebookDeletionRecovery(recovery:capsule)
        XCTAssertEqual(recovery.plan.notebook,before.records[0]); XCTAssertEqual(recovery.plan.entries,[before.records[1]])
        XCTAssertFalse(recovery.restored); XCTAssertFalse(value.records.contains(where:{$0.kind == NotebookDeletionRecovery.recoveryKind}))
        let restart = try JSONDecoder().decode(VaultSnapshot.self,from:JSONEncoder().encode(value)); XCTAssertEqual(restart,value)
        // Lost acknowledgements may mark dirty false, not change the checkpoint.
        value.records[0].dirty = false; value.records[1].dirty = false
        try value.restoreNotebookDeletion(capsule,now:Date(timeIntervalSince1970:101))
        XCTAssertFalse(value.records[0].deleted); XCTAssertFalse(value.records[1].deleted)
        XCTAssertEqual(value.records[0].id,before.records[0].id); XCTAssertEqual(value.records[1].id,before.records[1].id)
        for key in ["bodyJson","bodyText","labels","attachments","opaqueFuture","journalId"] { XCTAssertEqual(value.records[1].body[key],before.records[1].body[key]) }
        XCTAssertEqual(value.mediaUploads,before.mediaUploads); XCTAssertEqual(value.richDrafts,before.richDrafts)
        XCTAssertTrue(try NotebookDeletionRecovery(recovery:XCTUnwrap(value.conflicts.last)).restored)
        let completed = value; XCTAssertThrowsError(try value.restoreNotebookDeletion(capsule)); XCTAssertEqual(value,completed)
    }
    func testAddedMovedEditedDeletedDuplicateAndOverflowInputsRefuseAtomically() throws {
        let before = try snapshot(), plan = try NotebookDeletionPlan(snapshot:before,notebook:before.records[0])
        for mode in 0..<7 {
            var changed = before
            switch mode {
            case 0: changed.records.append(VaultRecord(id:"arrived-later",clock:1,body:["journalId":.string("original")]))
            case 1: changed.records[1].body["journalId"] = .string("elsewhere")
            case 2: changed.records[1].body["opaqueFuture"] = .string("newer same-clock edit")
            case 3: changed.records[1].deleted = true
            case 4: changed.records.append(changed.records[1])
            case 5: changed.records[0].clock += 1
            default: changed.records[1].clock = ProtocolNumbers.maxWireInteger
            }
            let checkpoint = changed
            if mode == 6 {
                let overflowPlan = try NotebookDeletionPlan(snapshot:changed,notebook:changed.records[0])
                XCTAssertThrowsError(try changed.deleteNotebookPreservingRecovery(overflowPlan))
            } else { XCTAssertThrowsError(try changed.deleteNotebookPreservingRecovery(plan)) }
            XCTAssertEqual(changed,checkpoint,"Failure must not partially tombstone a notebook or entry")
        }
    }
    func testRestoreRefusesRemoteChangesWithoutReversingAnyCurrentRecord() throws {
        var deleted = try snapshot(); let plan = try NotebookDeletionPlan(snapshot:deleted,notebook:deleted.records[0])
        try deleted.deleteNotebookPreservingRecovery(plan); let recovery = try XCTUnwrap(deleted.conflicts.last)
        for mode in 0..<4 {
            var changed = deleted
            if mode == 0 { changed.records[1].clock += 1 }
            if mode == 1 { changed.records[1].body["title"] = .string("Changed remotely") }
            if mode == 2 { changed.records.append(VaultRecord(id:"other-notebook-record",clock:1,body:["kind":.string("journal"),"journalId":.string("original")])) }
            if mode == 3 { changed.records.remove(at:1) }
            let checkpoint = changed; XCTAssertThrowsError(try changed.restoreNotebookDeletion(recovery)); XCTAssertEqual(changed,checkpoint)
        }
    }
    func testEmptyNotebookCascadeAndRecoveryCapacityNeverEvictOriginals() throws {
        var empty=try snapshot();empty.records.remove(at:1)
        let plan=try NotebookDeletionPlan(snapshot:empty,notebook:empty.records[0]);XCTAssertTrue(plan.entries.isEmpty)
        try empty.deleteNotebookPreservingRecovery(plan);let capsule=try XCTUnwrap(empty.conflicts.last)
        try empty.restoreNotebookDeletion(capsule);XCTAssertFalse(empty.records[0].deleted)
        var full=try snapshot();full.conflicts += (0..<128).map{VaultRecord(id:"preserved-notebook-recovery-\($0)",clock:1,body:["kind":.string(NotebookDeletionRecovery.recoveryKind)])}
        let checkpoint=full,fullPlan=try NotebookDeletionPlan(snapshot:full,notebook:full.records[0])
        XCTAssertThrowsError(try full.deleteNotebookPreservingRecovery(fullPlan));XCTAssertEqual(full,checkpoint)
    }

    func testCanonicallyEquivalentConcurrentChangesAreNotDiscarded() throws {
        var original = try snapshot();original.records[1].body["unicodeProbe"] = .string("é")
        let plan = try NotebookDeletionPlan(snapshot:original,notebook:original.records[0])
        var changed=original;changed.records[1].body["unicodeProbe"] = .string("e\u{301}")
        let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
        let checkpoint=try encoder.encode(changed)
        XCTAssertThrowsError(try changed.deleteNotebookPreservingRecovery(plan))
        XCTAssertEqual(try encoder.encode(changed),checkpoint)
        XCTAssertFalse(changed.records[0].deleted)
        try original.deleteNotebookPreservingRecovery(plan)
        let recovery=try XCTUnwrap(original.conflicts.last)
        original.records[1].body["unicodeProbe"] = .string("e\u{301}")
        XCTAssertThrowsError(try original.restoreNotebookDeletion(recovery));XCTAssertTrue(original.records[0].deleted)
    }

    func testTombstonesDoNotWaitForPendingMediaAndRestoreReactivatesUploadDependencies() throws {
        var value = try snapshot(); XCTAssertTrue(value.liveMediaUploadIDs.contains(mediaID))
        XCTAssertFalse(value.uploadableRecords.contains(where:{$0.id == "entry-original"}))
        let plan = try NotebookDeletionPlan(snapshot:value,notebook:value.records[0]); try value.deleteNotebookPreservingRecovery(plan)
        XCTAssertFalse(value.liveMediaUploadIDs.contains(mediaID),"Only deleted/recovered references must pause automatic upload, not purge it")
        XCTAssertTrue(value.uploadableRecords.contains(where:{$0.id == "entry-original" && $0.deleted}))
        XCTAssertEqual(value.mediaUploads?.count,1)
        let recovery = try XCTUnwrap(value.conflicts.last); try value.restoreNotebookDeletion(recovery)
        XCTAssertTrue(value.liveMediaUploadIDs.contains(mediaID)); XCTAssertFalse(value.uploadableRecords.contains(where:{$0.id == "entry-original"}))
        let upload = try XCTUnwrap(value.mediaUploads?.first); value.mediaUploaded(upload)
        XCTAssertTrue(value.uploadableRecords.contains(where:{$0.id == "entry-original"}))
        // A shared LIVE reference must still upload despite another deleted entry.
        value = try snapshot(); value.records[2].body["attachments"] = value.records[1].body["attachments"]
        try value.deleteNotebookPreservingRecovery(NotebookDeletionPlan(snapshot:value,notebook:value.records[0]))
        XCTAssertTrue(value.liveMediaUploadIDs.contains(mediaID))
    }
    func testEncryptedCascadeAndRestoreFailuresPreservePriorBytesAndRetry() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true); defer { try? FileManager.default.removeItem(at:directory) }
        let store = EncryptedSnapshotStore(directory:directory,namespace:"public-notebook-lifecycle",key:SymmetricKey(data:Data(repeating:29,count:32)))
        let before = try snapshot(); try store.save(before)
        let path = directory.appendingPathComponent("public-notebook-lifecycle.vault"), bytes = try Data(contentsOf:directory.appendingPathComponent("public-notebook-lifecycle.vault"))
        var deleted = before; try deleted.deleteNotebookPreservingRecovery(NotebookDeletionPlan(snapshot:before,notebook:before.records[0]))
        store.prepareWriteForTesting = {throw NSError(domain:"public-notebook-disk-fault",code:1)}
        XCTAssertThrowsError(try store.save(deleted)); XCTAssertEqual(try Data(contentsOf:path),bytes); XCTAssertEqual(try store.load(),before)
        store.prepareWriteForTesting = nil; try store.save(deleted); XCTAssertEqual(try store.load(),deleted)
        let deletedBytes = try Data(contentsOf:path); var restored = deleted; try restored.restoreNotebookDeletion(XCTUnwrap(deleted.conflicts.last))
        store.prepareWriteForTesting = {throw NSError(domain:"public-notebook-restore-fault",code:1)}
        XCTAssertThrowsError(try store.save(restored)); XCTAssertEqual(try Data(contentsOf:path),deletedBytes); XCTAssertEqual(try store.load(),deleted)
        store.prepareWriteForTesting = nil; try store.save(restored); XCTAssertEqual(try store.load(),restored)
        XCTAssertNil(try Data(contentsOf:path).range(of:Data("Original notebook".utf8)))
    }
    func testNotebookCiphertextOriginalWebDeletionAndRestoreCompatibility() throws {
        guard let path = ProcessInfo.processInfo.environment["CHAPTER_NATIVE_OUTPUT"] else { return }
        var value = try snapshot(); let before = value
        let plan = try NotebookDeletionPlan(snapshot:value,notebook:value.records[0]); try value.deleteNotebookPreservingRecovery(plan,now:Date(timeIntervalSince1970:100))
        let identity = try VaultIdentity(seed:RecoveryPhrase.seed("legal winner thank year wave sausage worth useful legal winner thank yellow"))
        func wire(_ value:VaultRecord) throws -> JSONValue {
            let cipher = try VaultCipher.sealRecord(JSONEncoder().encode(value.body),key:identity.dataKey,id:value.id)
            return .object(["id":.string(value.id),"deleted":.bool(value.deleted),"clock":.number(Double(value.clock)),"record":.string(cipher.base64EncodedString())])
        }
        let deletion = try value.records.prefix(2).map(wire)
        try value.restoreNotebookDeletion(XCTUnwrap(value.conflicts.last),now:Date(timeIntervalSince1970:101))
        let output: JSONValue = .object(["original":.array(before.records.prefix(2).map { .object($0.body) }),"deleted":.array(deletion),"restored":.array(try value.records.prefix(2).map(wire))])
        try JSONEncoder().encode(output).write(to:URL(fileURLWithPath:path+".notebook-lifecycle"))
    }
}
