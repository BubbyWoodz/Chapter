// SPDX-License-Identifier: AGPL-3.0-or-later
import XCTest
@testable import ChapterCore

final class LiveRelayTests: XCTestCase {
    func testRealTLSRelayAuthMultiPageDrainAndEncryptedMedia() async throws {
        guard let base = ProcessInfo.processInfo.environment["CHAPTER_NATIVE_LIVE_URL"] else {
            throw XCTSkip("Live relay not requested; CI separately runs this against isolated PostgreSQL + loopback TLS")
        }
        let client = Relay(address: try ServerAddress(base)); defer { client.cancel() }
        let identity = try VaultIdentity(seed: RecoveryPhrase.seed("legal winner thank year wave sausage worth useful legal winner thank yellow"))
        let token = try await client.authenticate(identity)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("public-source")
        let plain = Data(repeating: 77, count: MediaLimits.chunkBytes + 17); try plain.write(to: source)
        let files = try EncryptedMediaFiles(directory: directory, namespace: "live-only")
        let upload = try files.stage(source: source, id: UUID().uuidString.replacingOccurrences(of:"-",with:""), name:"Public live media", mime:"application/octet-stream", key:identity.mediaKey)
        let raw = #"{"type":"doc","future":{"keep":true},"content":[{"type":"paragraph","content":[{"type":"text","text":"Public live content"}]}]}"#
        var snapshot = VaultSnapshot()
        snapshot.records = (0..<205).map { VaultRecord(id: String(format:"native_live_%05d",$0), clock:Int64($0+1), body:["title":.string("Public fixture"),"bodyJson":.string(raw),"unknownFuture":.bool(true)], dirty:true) }
        let mediaEntry = snapshot.records[0].id
        try snapshot.attach(upload, entryID:mediaEntry, expectedDocument:raw)
        var queue = SyncPushQueue(), batches = 0
        while true {
            let batch = try queue.next(from:snapshot); if batch.isEmpty { break }
            batches += 1
            let results = try await client.push(batch, identity:identity, token:token)
            XCTAssertTrue(results.allSatisfy(\.applied))
            for record in batch { snapshot.acknowledge(record) }
        }
        XCTAssertEqual(batches,3); XCTAssertEqual(snapshot.records.filter(\.dirty).map(\.id),[mediaEntry])
        var cursor: Int64 = 0, received: [PullRecord] = [], pages = 0
        while true {
            let page = try await client.pull(since:cursor, token:token); pages += 1
            received += page.entries; cursor = page.cursor
            if !page.more { break }
            guard pages < 10 else {
                XCTFail("Live relay exceeded bounded pagination"); return
            }
        }
        XCTAssertEqual(pages,3); XCTAssertEqual(received.count,204)
        XCTAssertFalse(received.contains { $0.entry_id == mediaEntry },"Pending media references must not appear on the actual server")
        for record in received {
            let cipher = try XCTUnwrap(Data(base64Encoded:record.ciphertext))
            let body = try JSONDecoder().decode([String:JSONValue].self,from:VaultCipher.openRecord(cipher,key:identity.dataKey,id:record.entry_id))
            XCTAssertEqual(body["unknownFuture"],.bool(true)); XCTAssertEqual(body["bodyJson"]?.string,raw)
        }
        try await client.uploadMedia(upload,files:files,mediaKey:identity.mediaKey,token:token)
        // Simulate process interruption after remote completion, before queue ack.
        // The real relay serves existing bytes; recovery must not regenerate them.
        try await client.uploadMedia(upload,files:files,mediaKey:identity.mediaKey,token:token)
        let metadata = try await client.mediaMetadata(id:upload.id,token:token)
        XCTAssertEqual(metadata.cipherBytes,Int64(plain.count+41*upload.chunks))
        var reopened = Data(), chunks: [String] = []
        for index in 0..<upload.chunks {
            let cipher = try await client.mediaChunk(id:upload.id,index:index,token:token)
            XCTAssertEqual(cipher,try files.read(id:upload.id,index:index)); chunks.append(cipher.base64EncodedString())
            reopened.append(try VaultCipher.openMediaChunk(cipher,key:identity.mediaKey,id:upload.id,index:index,total:upload.chunks))
        }
        XCTAssertEqual(reopened,plain)
        snapshot.mediaUploaded(upload)
        let finalBatch = try queue.next(from:snapshot); XCTAssertEqual(finalBatch.map(\.id),[mediaEntry])
        let finalResults = try await client.push(finalBatch,identity:identity,token:token)
        XCTAssertTrue(finalResults.allSatisfy(\.applied))
        for record in finalBatch { snapshot.acknowledge(record) }
        XCTAssertTrue(snapshot.records.allSatisfy { !$0.dirty })
        let last = try await client.pull(since:cursor,token:token)
        XCTAssertEqual(last.entries.count,1); XCTAssertEqual(last.entries[0].entry_id,mediaEntry)
        // Real notebook lifecycle through normally trusted TLS/Go/Postgres;
        // pending media must not prevent tombstones or erase shared media.
        let notebookID = UUID().uuidString.replacingOccurrences(of:"-",with:"")
        let entryID = UUID().uuidString.replacingOccurrences(of:"-",with:"")
        let logicalID = UUID().uuidString.replacingOccurrences(of:"-",with:"")
        let clock = try ProtocolNumbers.nextClock(after:0)
        var lifecycle = VaultSnapshot()
        lifecycle.records = [VaultRecord(id:notebookID,clock:clock,body:["kind":.string("journal"),"journalId":.string(logicalID),"name":.string("Public live notebook"),"cover":.string("lines"),"opaqueFuture":.bool(true)],dirty:true),VaultRecord(id:entryID,clock:clock,body:["journalId":.string(logicalID),"title":.string("Public live notebook entry"),"bodyJson":.string(raw),"bodyText":.string("Public live content"),"labels":.array([.string("travel, friends")]),"attachments":.array([.object(upload.attributes)]),"opaqueFuture":.bool(true)],dirty:true)]
        let originalLifecycle = lifecycle.records
        let originalResults = try await client.push(lifecycle.records,identity:identity,token:token)
        XCTAssertEqual(originalResults.count,2); XCTAssertTrue(originalResults.allSatisfy(\.applied))
        for record in originalLifecycle { lifecycle.acknowledge(record) }
        let originalPage = try await client.pull(since:last.cursor,token:token); XCTAssertEqual(originalPage.entries.count,2)
        lifecycle.mediaUploads = [upload] // lost local completion ack, original chunks retained
        let plan = try NotebookDeletionPlan(snapshot:lifecycle,notebook:lifecycle.records[0])
        try lifecycle.deleteNotebookPreservingRecovery(plan)
        var deletionQueue = SyncPushQueue()
        let deleteBatch = try deletionQueue.next(from:lifecycle)
        XCTAssertEqual(deleteBatch.count,2); XCTAssertTrue(deleteBatch.allSatisfy(\.deleted))
        let deleteResults = try await client.push(deleteBatch,identity:identity,token:token)
        XCTAssertTrue(deleteResults.allSatisfy(\.applied)); for record in deleteBatch { lifecycle.acknowledge(record) }
        let deletedPage = try await client.pull(since:originalPage.cursor,token:token)
        XCTAssertEqual(deletedPage.entries.count,2); XCTAssertTrue(deletedPage.entries.allSatisfy(\.deleted))
        let retainedSharedMedia = try await client.mediaMetadata(id:upload.id,token:token)
        XCTAssertEqual(retainedSharedMedia.cipherBytes,metadata.cipherBytes)
        try lifecycle.restoreNotebookDeletion(XCTUnwrap(lifecycle.conflicts.last))
        XCTAssertFalse(lifecycle.uploadableRecords.contains(where:{$0.id == entryID}))
        try await client.uploadMedia(upload,files:files,mediaKey:identity.mediaKey,token:token); lifecycle.mediaUploaded(upload)
        let restoreResults = try await client.push(lifecycle.records,identity:identity,token:token)
        XCTAssertTrue(restoreResults.allSatisfy(\.applied))
        let restoredPage = try await client.pull(since:deletedPage.cursor,token:token)
        XCTAssertEqual(restoredPage.entries.count,2); XCTAssertTrue(restoredPage.entries.allSatisfy({!$0.deleted}))
        func stage(_ page:[PullRecord]) throws -> [JSONValue] {
            try [notebookID,entryID].map { id in
                let wire = try XCTUnwrap(page.first(where:{$0.entry_id == id}))
                return .object(["id":.string(id),"record":.string(wire.ciphertext),"clock":.number(Double(wire.lww_clock)),"deleted":.bool(wire.deleted)])
            }
        }
        if let output = ProcessInfo.processInfo.environment["CHAPTER_NATIVE_OUTPUT"] {
            let vector:JSONValue = .object(["original":.array(originalLifecycle.map{.object($0.body)}),"deleted":.array(try stage(deletedPage.entries)),"restored":.array(try stage(restoredPage.entries))])
            try JSONEncoder().encode(vector).write(to:URL(fileURLWithPath:output+".notebook-live-lifecycle"))
        }
        if let output = ProcessInfo.processInfo.environment["CHAPTER_NATIVE_OUTPUT"] {
            let vector:[String:JSONValue] = ["recordId":.string(mediaEntry),"ciphertext":.string(last.entries[0].ciphertext),"mediaId":.string(upload.id),"chunks":.array(chunks.map(JSONValue.string))]
            try JSONEncoder().encode(vector).write(to:URL(fileURLWithPath:output+".live"))
        }
    }
}
final class SyncDrainTests: XCTestCase {
    func testDrainIncludesLaterBatchesWithoutRetryingRejectedIDsForever() throws {
        var snapshot = VaultSnapshot()
        snapshot.records = (0..<205).map { VaultRecord(id:"record-\($0)",clock:1,body:[:],dirty:true) }
        var queue = SyncPushQueue()
        XCTAssertEqual(try queue.next(from:snapshot).count,100)
        XCTAssertEqual(try queue.next(from:snapshot).count,100)
        XCTAssertEqual(try queue.next(from:snapshot).count,5)
        XCTAssertTrue(try queue.next(from:snapshot).isEmpty)
        XCTAssertEqual(snapshot.records.filter(\.dirty).count,205,"Rejected/unknown acknowledgments must not discard changes")
        snapshot.records[0].clock = 2
        XCTAssertTrue(try queue.next(from:snapshot).isEmpty,"Concurrent edits remain dirty for a subsequent pass")
    }
    func testForegroundBackoffIsBoundedAndResetsWithoutOverflow() {
        var retry = SyncBackoff(); XCTAssertEqual(retry.seconds,30)
        for _ in 0..<1000 { retry.failed(); XCTAssertTrue((30...300).contains(retry.seconds)) }
        XCTAssertEqual(retry.seconds,300); retry.succeeded(); XCTAssertEqual(retry.seconds,30)
    }
    func testDrainHasBoundedPassAndLeavesUnattemptedWorkIntact() throws {
        var snapshot = VaultSnapshot()
        snapshot.records = (0..<10_001).map { VaultRecord(id:"record-\($0)",clock:1,body:[:],dirty:true) }
        var queue = SyncPushQueue()
        for _ in 0..<100 { XCTAssertEqual(try queue.next(from:snapshot).count,100) }
        XCTAssertThrowsError(try queue.next(from:snapshot))
        XCTAssertEqual(snapshot.records.filter(\.dirty).count,10_001)
    }
}
