// SPDX-License-Identifier: AGPL-3.0-or-later
import XCTest
import CryptoKit
@testable import ChapterCore

final class MediaPurgeTests:XCTestCase {
    let id=String(repeating:"a",count:32)
    var cache:MediaCache {MediaCache(id:id,chunks:1,cipherBytes:42)}
    func snapshot()->VaultSnapshot {var value=VaultSnapshot();value.mediaCache=[cache];return value}
    func bytes<T:Encodable>(_ value:T)throws->Data {let e=JSONEncoder();e.outputFormatting=[.sortedKeys];return try e.encode(value)}
    func testQueuedSendingConfirmedAndCompletionPreserveUnrelatedCacheAndUploads() throws {
        var state=snapshot();let other=MediaCache(id:String(repeating:"b",count:32),chunks:1,cipherBytes:42)
        state.mediaCache?.append(other)
        state.mediaUploads=[MediaUpload(id:String(repeating:"c",count:32),chunks:1,cipherBytes:42,plainBytes:1,name:"UNSENT",mime:"text/plain")]
        let uploads=state.mediaUploads,review=try state.reviewMediaPurge(cache),queued=try state.queueMediaPurge(review)
        XCTAssertEqual(try state.mediaPurgeIntents(),[queued]);XCTAssertTrue(state.uploadableRecords.isEmpty)
        let sending=try state.beginMediaPurge(queued);XCTAssertEqual(sending.phase,.sending)
        XCTAssertThrowsError(try state.cancelMediaPurge(sending));XCTAssertThrowsError(try state.confirmMediaPurge(queued))
        let retried=try state.beginMediaPurge(sending);XCTAssertEqual(retried.media,sending.media);XCTAssertGreaterThan(retried.revision,sending.revision)
        let confirmed=try state.confirmMediaPurge(retried);XCTAssertEqual(state.mediaCache?.count,2)
        XCTAssertThrowsError(try state.beginMediaPurge(confirmed));try state.finishMediaPurge(confirmed)
        XCTAssertEqual(state.mediaCache,[other]);XCTAssertEqual(state.mediaUploads,uploads);XCTAssertTrue(state.conflicts.isEmpty)
    }
    func testCancelOnlyBeforeSendingAndReviewIsExactIncludingUnicodeAndCursor() throws {
        var state=snapshot();state.records=[VaultRecord(id:"entry",clock:1,body:["bodyText":.string("é")])]
        let review=try state.reviewMediaPurge(cache);state.records[0].body["bodyText"] = .string("e\u{0301}")
        let changed=try bytes(state);XCTAssertThrowsError(try state.queueMediaPurge(review));XCTAssertEqual(try bytes(state),changed)
        let fresh=try state.reviewMediaPurge(cache);state.cursor+=1;XCTAssertThrowsError(try state.queueMediaPurge(fresh))
        let queued=try state.queueMediaPurge(state.reviewMediaPurge(cache));try state.cancelMediaPurge(queued)
        XCTAssertEqual(state.mediaCache,[cache]);XCTAssertTrue(state.conflicts.isEmpty)
    }
    func testSharedDeletedRecoveryPendingAndEscapedReferencesNeverPurge() throws {
        let reference=VaultRecord(id:"entry",clock:1,body:["attachments":.array([.object(["id":.string(id),"bytes":.number(1)])])])
        var deleted=reference;deleted.deleted=true
        var dirty=VaultRecord(id:"dirty",clock:1,body:[:]);dirty.dirty=true
        let escaped=id.map{_ in "\\u0061"}.joined()
        let escapedJSON="{\"type\":\"doc\",\"content\":[{\"type\":\"mediaAttachment\",\"attrs\":{\"id\":\""+escaped+"\"}}]}"
        let encoded=VaultRecord(id:"escaped",clock:1,body:["bodyJson":.string(escapedJSON)])
        for records in [[reference],[deleted],[dirty],[encoded]] {
            var state=snapshot();state.records=records;let before=try bytes(state)
            XCTAssertThrowsError(try state.reviewMediaPurge(cache));XCTAssertEqual(try bytes(state),before)
        }
        var state=snapshot();state.conflicts=[reference];XCTAssertThrowsError(try state.reviewMediaPurge(cache))
        state=snapshot();state.richDrafts=[RichDraft(entryID:"entry",path:[0],expectedDocument:"{}",text:"UNSENT")]
        XCTAssertThrowsError(try state.reviewMediaPurge(cache))
        state=snapshot();state.mediaUploads=[MediaUpload(id:id,chunks:1,cipherBytes:42,plainBytes:1,name:"UNSENT",mime:"text/plain")]
        XCTAssertThrowsError(try state.reviewMediaPurge(cache))
    }
    func testOpaqueFutureFieldsAndUnknownNodesFailClosedEvenWithoutVisibleID() throws {
        for body:[String:JSONValue] in [
            ["futureMedia":.object(["encoded":.string("opaque")])],
            ["bodyJson":.string(#"{"type":"doc","content":[{"type":"futureEncryptedGallery","attrs":{"opaque":"payload"}}]}"#)],
            ["bodyJson":.string(#"{"type":"doc","attrs":{"futureMedia":"opaque"}}"#)],
            ["bodyJson":.string(#"{"type":"doc","content":[{"type":"mediaGallery","attrs":{"images":[{"futureEncodedRef":"opaque"}]}}]}"#)],
            ["bodyJson":.array([])],
            ["attachments":.object([:])],
            ["bodyJson":.string("invalid")]
        ] {
            var state=snapshot();state.records=[VaultRecord(id:"future",clock:1,body:body)]
            XCTAssertThrowsError(try state.reviewMediaPurge(cache))
        }
        var state=snapshot();state.conflicts=[VaultRecord(id:"local-draft",clock:1,body:["kind":.string(PlainEntryDraft.recoveryKind)])]
        XCTAssertThrowsError(try state.reviewMediaPurge(cache))
    }
    func testStaleAndMalformedMetadataOrIntentNeverMutatesOrDisappears() throws {
        for bad in [MediaCache(id:"../escape",chunks:1,cipherBytes:42),MediaCache(id:id,chunks:Int.max,cipherBytes:Int64.max),MediaCache(id:id,chunks:1,cipherBytes:Int64.min),MediaCache(id:id,chunks:2,cipherBytes:82)] {
            var state=snapshot();state.mediaCache=[bad];XCTAssertThrowsError(try state.reviewMediaPurge(bad))
        }
        var state=snapshot();let queued=try state.queueMediaPurge(state.reviewMediaPurge(cache))
        XCTAssertThrowsError(try state.reviewMediaPurge(cache));state.conflicts.append(try queued.recoveryRecord())
        XCTAssertThrowsError(try state.mediaPurgeIntents())
        state=snapshot();state.conflicts=[VaultRecord(id:"bad",clock:1,body:["kind":.string(MediaPurgeIntent.recoveryKind)])]
        XCTAssertThrowsError(try state.mediaPurgeIntents());XCTAssertThrowsError(try state.reviewMediaPurge(cache))
        state=snapshot();var maximum=try queued.recoveryRecord();maximum.clock=ProtocolNumbers.maxWireInteger
        if case .object(var payload)=maximum.body["localMediaPurge"]! {payload["revision"] = .number(Double(ProtocolNumbers.maxWireInteger));maximum.body["localMediaPurge"] = .object(payload)}
        state.conflicts=[maximum];let frozen=try bytes(state),intent=try XCTUnwrap(state.mediaPurgeIntents().first)
        XCTAssertThrowsError(try state.beginMediaPurge(intent));XCTAssertEqual(try bytes(state),frozen)
    }
    func testReferenceArrivalAfterSendingRetainsIntentAndEncryptedCacheInsteadOfAcknowledging() throws {
        var state=snapshot();let queued=try state.queueMediaPurge(state.reviewMediaPurge(cache)),sending=try state.beginMediaPurge(queued)
        state.records=[VaultRecord(id:"arrived",clock:2,body:["attachments":.array([.object(["id":.string(id)])])])]
        let before=try bytes(state);XCTAssertThrowsError(try state.confirmMediaPurge(sending));XCTAssertEqual(try bytes(state),before)
        XCTAssertEqual(state.mediaCache,[cache]);XCTAssertEqual(try state.mediaPurgeIntents(),[sending])
    }
    func testOlderOpaqueRecoveryRoundtripRetainsIntentButCannotRestoreAsJournalEntry() throws {
        var state=snapshot();let queued=try state.queueMediaPurge(state.reviewMediaPurge(cache))
        struct OlderSnapshot:Codable {var version:Int;var records:[VaultRecord];var cursor:Int64;var conflicts:[VaultRecord];var mediaCache:[MediaCache]?}
        let old=try JSONDecoder().decode(OlderSnapshot.self,from:JSONEncoder().encode(state))
        let reopened=try JSONDecoder().decode(VaultSnapshot.self,from:JSONEncoder().encode(old))
        XCTAssertEqual(try reopened.mediaPurgeIntents(),[queued]);XCTAssertEqual(reopened.mediaCache,[cache])
        XCTAssertThrowsError(try old.conflicts[0].restoredEntry(id:"not-an-entry"))
    }
    func testEncryptedIntentFaultAndInterruptedDeleteRetryAreDurableWithOriginalKey() throws {
        let dir=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:dir)}
        let key=SymmetricKey(size:.bits256),disk=EncryptedSnapshotStore(directory:dir,namespace:"purge",key:key)
        var state=snapshot();let queued=try state.queueMediaPurge(state.reviewMediaPurge(cache));try disk.save(state)
        let file=dir.appendingPathComponent("purge.vault"),old=try Data(contentsOf:file)
        var next=state;let sending=try next.beginMediaPurge(queued)
        disk.prepareWriteForTesting={throw ChapterError.storage};XCTAssertThrowsError(try disk.save(next))
        XCTAssertEqual(try Data(contentsOf:file),old);XCTAssertEqual(try disk.load().mediaPurgeIntents(),[queued])
        disk.prepareWriteForTesting=nil;try disk.save(next)
        var reopened=try EncryptedSnapshotStore(directory:dir,namespace:"purge",key:key).load()
        let retried=try reopened.beginMediaPurge(sending);try disk.save(reopened)
        let confirmed=try reopened.confirmMediaPurge(retried);try disk.save(reopened)
        XCTAssertEqual(try disk.load().mediaPurgeIntents(),[confirmed]);XCTAssertEqual(try disk.load().mediaCache,[cache])
        var finished=reopened;try finished.finishMediaPurge(confirmed)
        disk.prepareWriteForTesting={throw ChapterError.storage};XCTAssertThrowsError(try disk.save(finished))
        XCTAssertEqual(try disk.load().mediaPurgeIntents(),[confirmed])
        disk.prepareWriteForTesting=nil;try disk.save(finished);XCTAssertTrue(try disk.load().mediaPurgeIntents().isEmpty)
        XCTAssertFalse(try Data(contentsOf:file).contains(Data(id.utf8)))
    }
    func testEncryptedFilesRemainForNewReferencesAndCleanupRetriesAfterLostAcknowledgement() throws {
        let dir=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:dir)}
        let files=try EncryptedMediaFiles(directory:dir,namespace:"purge-files"),source=dir.appendingPathComponent("public-fixture")
        try Data([42]).write(to:source)
        let upload=try files.stage(source:source,id:id,name:"Public fixture",mime:"application/octet-stream",key:Data(repeating:7,count:32))
        var state=snapshot();let queued=try state.queueMediaPurge(state.reviewMediaPurge(cache))
        XCTAssertThrowsError(try files.removeConfirmedPurge(queued,snapshot:state))
        let sending=try state.beginMediaPurge(queued),confirmed=try state.confirmMediaPurge(sending)
        var referenced=state;referenced.records=[VaultRecord(id:"late",clock:1,body:["attachments":.array([.object(["id":.string(id)])])])]
        XCTAssertThrowsError(try files.removeConfirmedPurge(confirmed,snapshot:referenced))
        XCTAssertEqual(try files.read(id:id,index:0).count,Int(upload.cipherBytes))
        try files.removeConfirmedPurge(confirmed,snapshot:state)
        // Simulate lost snapshot finish acknowledgement: same confirmed state,
        // already missing files, exact intent is retried safely after restart.
        try files.removeConfirmedPurge(confirmed,snapshot:state)
        XCTAssertThrowsError(try files.read(id:id,index:0));try state.finishMediaPurge(confirmed)
        XCTAssertTrue(try state.mediaPurgeIntents().isEmpty)
    }

}
