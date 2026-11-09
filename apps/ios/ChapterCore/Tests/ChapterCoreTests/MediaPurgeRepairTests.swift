// SPDX-License-Identifier: AGPL-3.0-or-later
import XCTest
import CryptoKit
@testable import ChapterCore
final class MediaPurgeRepairTests:XCTestCase {
    let id=String(repeating:"a",count:32)
    func sending() throws -> (VaultSnapshot,MediaPurgeIntent) {
        var state=VaultSnapshot();state.mediaCache=[MediaCache(id:id,chunks:1,cipherBytes:42)]
        let queued=try state.queueMediaPurge(state.reviewMediaPurge(state.mediaCache![0]))
        let sent=try state.beginMediaPurge(queued);return(state,sent)
    }
    func reference(dirty:Bool=false)->VaultRecord {VaultRecord(id:"concurrent",clock:3,body:["attachments":.array([.object(["id":.string(id)])]),"future":.string("preserve")],dirty:dirty)}
    func testInFlightReferenceRepairRetainsEveryOriginalFieldAndCache() throws {
        var (state,sent)=try sending();let record=reference();state.records=[record]
        let cached=state.mediaCache;XCTAssertThrowsError(try state.confirmMediaPurge(sent))
        let repair=try state.beginMediaPurgeRepair(sent);XCTAssertEqual(repair.phase,.repairing)
        XCTAssertThrowsError(try state.beginMediaPurge(repair));XCTAssertThrowsError(try state.cancelMediaPurge(repair))
        XCTAssertThrowsError(try state.finishMediaPurge(repair))
        let again=try state.beginMediaPurgeRepair(repair);try state.finishMediaPurgeRepair(again)
        XCTAssertEqual(state.records,[record]);XCTAssertEqual(state.mediaCache,cached);XCTAssertTrue(state.conflicts.isEmpty)
    }
    func testFreshReferencingPushIsGatedUntilRepairCompletion() throws {
        var (state,sent)=try sending();state.records=[reference(dirty:true)]
        XCTAssertTrue(state.uploadableRecords.isEmpty)
        let repair=try state.beginMediaPurgeRepair(sent);XCTAssertTrue(state.uploadableRecords.isEmpty)
        try state.finishMediaPurgeRepair(repair);XCTAssertEqual(state.uploadableRecords,state.records)
    }
    func testMalformedOrStaleRepairNeverDropsIntentOrPendingWork() throws {
        var (state,sent)=try sending();let repair=try state.beginMediaPurgeRepair(sent)
        state.richDrafts=[RichDraft(entryID:"pending",path:[0],expectedDocument:"{}",text:"UNSENT")]
        state.mediaUploads=[MediaUpload(id:String(repeating:"b",count:32),chunks:1,cipherBytes:42,plainBytes:1,name:"UNSENT",mime:"text/plain")]
        let drafts=state.richDrafts,uploads=state.mediaUploads
        XCTAssertThrowsError(try state.finishMediaPurgeRepair(sent));XCTAssertEqual(try state.mediaPurgeIntents(),[repair])
        try state.finishMediaPurgeRepair(repair);XCTAssertEqual(state.richDrafts,drafts);XCTAssertEqual(state.mediaUploads,uploads)
    }
    func testConfirmedLostAcknowledgementCanRestoreInsteadOfDeletingNewReference() throws {
        var (state,sent)=try sending();let confirmed=try state.confirmMediaPurge(sent)
        state.records=[reference()];XCTAssertThrowsError(try state.finishMediaPurge(confirmed))
        let repair=try state.beginMediaPurgeRepair(confirmed);try state.finishMediaPurgeRepair(repair)
        XCTAssertEqual(state.records,[reference()]);XCTAssertEqual(state.mediaCache?.count,1)
    }
    func testQueuedIntentCannotBeUsedToFabricateRepairCompletion() throws {
        var state=VaultSnapshot();state.mediaCache=[MediaCache(id:id,chunks:1,cipherBytes:42)]
        let queued=try state.queueMediaPurge(state.reviewMediaPurge(state.mediaCache![0]))
        XCTAssertThrowsError(try state.beginMediaPurgeRepair(queued));XCTAssertThrowsError(try state.finishMediaPurgeRepair(queued))
        XCTAssertEqual(try state.mediaPurgeIntents(),[queued])
    }
    func testEncryptedRepairFaultRestartAndLostAcknowledgementPreserveBothSides() throws {
        let dir=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:dir)}
        let key=SymmetricKey(size:.bits256),disk=EncryptedSnapshotStore(directory:dir,namespace:"repair",key:key)
        var (state,sent)=try sending();state.records=[reference(dirty:true)];try disk.save(state)
        let old=try Data(contentsOf:dir.appendingPathComponent("repair.vault"));var next=state
        let repairing=try next.beginMediaPurgeRepair(sent)
        disk.prepareWriteForTesting={throw ChapterError.storage};XCTAssertThrowsError(try disk.save(next))
        XCTAssertEqual(try Data(contentsOf:dir.appendingPathComponent("repair.vault")),old)
        disk.prepareWriteForTesting=nil;try disk.save(next)
        var reopened=try EncryptedSnapshotStore(directory:dir,namespace:"repair",key:key).load()
        XCTAssertEqual(try reopened.mediaPurgeIntents(),[repairing]);XCTAssertTrue(reopened.uploadableRecords.isEmpty)
        let retry=try reopened.beginMediaPurgeRepair(repairing);try disk.save(reopened)
        var finished=reopened;try finished.finishMediaPurgeRepair(retry)
        disk.prepareWriteForTesting={throw ChapterError.storage};XCTAssertThrowsError(try disk.save(finished))
        XCTAssertEqual(try disk.load().mediaPurgeIntents(),[retry]);XCTAssertEqual(try disk.load().records,state.records)
        disk.prepareWriteForTesting=nil;try disk.save(finished)
        XCTAssertEqual(try disk.load().uploadableRecords,state.records);XCTAssertEqual(try disk.load().mediaCache,state.mediaCache)
    }
}
