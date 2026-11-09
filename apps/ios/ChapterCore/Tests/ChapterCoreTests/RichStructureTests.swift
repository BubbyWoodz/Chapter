// SPDX-License-Identifier: AGPL-3.0-or-later
import XCTest
import CryptoKit
@testable import ChapterCore

final class RichStructureTests: XCTestCase {
    func fixture() throws -> [String: JSONValue] {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "rich-document", withExtension: "json"))
        return try JSONDecoder().decode([String: JSONValue].self, from: Data(contentsOf: url))
    }
    func encoded<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]; return try encoder.encode(value)
    }
    func entry(_ raw: String, clock: Int64 = 1) -> VaultRecord {
        VaultRecord(id: "native-structure", clock: clock, body: ["bodyJson": .string(raw), "unknownFuture": .object(["preserve": .bool(true)])])
    }
    func testMultiBlockMovePreservesExactWholeNodesAndOriginalWebCiphertext() throws {
        let f = try fixture(), raw = String(decoding: try encoded(f["original"]!), as: UTF8.self)
        var snapshot = VaultSnapshot(); snapshot.records = [entry(raw)]
        let changed = try snapshot.reorderRichBlocks(expected: snapshot.records[0], from: IndexSet([0,2]), to: 14)
        let doc = try RichDocument(json: XCTUnwrap(changed.body["bodyJson"]?.string))
        XCTAssertEqual(try encoded(doc.root), try encoded(f["reordered"]!)); XCTAssertEqual(doc.plainText, f["reorderedPreview"]?.string)
        XCTAssertEqual(try encoded(doc.node.children[11].value), try encoded(f["original"]!["content"].array[13]), "Opaque future node unchanged")
        XCTAssertEqual(changed.body["unknownFuture"], .object(["preserve": .bool(true)]))
        XCTAssertEqual(Set(changed.mediaReferences.map(\.id)), Set(entry(raw).mediaReferences.map(\.id)))
        if let path = ProcessInfo.processInfo.environment["CHAPTER_NATIVE_OUTPUT"] {
            let url = try XCTUnwrap(Bundle.module.url(forResource: "web-v1", withExtension: "json"))
            let base = try JSONDecoder().decode(ChapterCoreTests.Fixture.self, from: Data(contentsOf: url))
            let identity = try VaultIdentity(seed: RecoveryPhrase.seed(base.phrase))
            let cipher = try VaultCipher.sealRecord(JSONEncoder().encode(changed.body), key: identity.dataKey, id: changed.id)
            try JSONEncoder().encode(["id":changed.id,"record":cipher.base64EncodedString()]).write(to: URL(fileURLWithPath:path+".rich-structure"))
        }
    }
    func testMoveInsertionOffsetSemanticsNoopsAndInvalidInputAreAtomic() throws {
        let raw = #"{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":"A"}]},{"type":"paragraph","content":[{"type":"text","text":"B"}]},{"type":"paragraph","content":[{"type":"text","text":"C"}]}]}"#
        var doc = try RichDocument(json: raw)
        XCTAssertTrue(try doc.moveBlocks(from: IndexSet(integer:0),to:2)); XCTAssertEqual(doc.plainText,"B\nA\nC")
        XCTAssertTrue(try doc.moveBlocks(from: IndexSet(integer:1),to:0)); XCTAssertEqual(doc.plainText,"A\nB\nC")
        let original = try encoded(doc.root)
        for move in [(IndexSet(),0),(IndexSet(integer:3),0),(IndexSet(integer:Int.max/2),0),(IndexSet(integer:0),-1),(IndexSet(integer:0),Int.max)] {
            XCTAssertThrowsError(try doc.moveBlocks(from:move.0,to:move.1)); XCTAssertEqual(try encoded(doc.root),original)
        }
        XCTAssertFalse(try doc.moveBlocks(from:IndexSet([0,1]),to:2)); XCTAssertEqual(try encoded(doc.root),original)
        var snapshot = VaultSnapshot(); snapshot.records = [entry(raw)]
        XCTAssertEqual(try snapshot.reorderRichBlocks(expected:snapshot.records[0],from:IndexSet(integer:0),to:1),snapshot.records[0])
        XCTAssertEqual(snapshot.records[0].clock,1)
    }
    func testStaleDeletedDuplicateAndOverflowNeverMutateSnapshot() throws {
        let raw = #"{"type":"doc","content":[{"type":"paragraph"},{"type":"horizontalRule"}]}"#
        let expected = entry(raw)
        var stale=expected;stale.body["title"] = .string("Another client")
        var deleted=expected;deleted.deleted=true
        let overflow=entry(raw,clock:9_007_199_254_740_991)
        for records in [[stale],[deleted],[expected,expected],[overflow]] {
            var snapshot=VaultSnapshot();snapshot.records=records;let before=try encoded(snapshot)
            XCTAssertThrowsError(try snapshot.reorderRichBlocks(expected:records.count == 1 && records[0].clock == overflow.clock ? overflow:expected,from:IndexSet(integer:0),to:2))
            XCTAssertEqual(try encoded(snapshot),before)
        }
    }
    func testCanonicalUnicodeDifferenceIsNotAnUnchangedCheckpointOrDocument() throws {
        let nfc = #"{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":"é"}]},{"type":"horizontalRule"}]}"#
        let nfd = nfc.replacingOccurrences(of:"é",with:"e\u{0301}")
        XCTAssertEqual(nfc,nfd); XCTAssertNotEqual(Data(nfc.utf8),Data(nfd.utf8))
        let expected=entry(nfc);var remote=entry(nfd);remote.dirty=true
        XCTAssertThrowsError(try remote.requiringUnchanged(expected:expected))
        XCTAssertThrowsError(try remote.editingRichDocument(expected:nfc) {try $0.moveBlocks(from:IndexSet(integer:0),to:2)})
        var acknowledged=expected;acknowledged.dirty=true
        XCTAssertNoThrow(try acknowledged.requiringUnchanged(expected:expected))
    }
    func testReorderingRetainsPendingDraftsUploadsCacheConflictsAndRejectsStalePaths() throws {
        let f=try fixture(),raw=String(decoding:try encoded(f["original"]!),as:UTF8.self),record=entry(raw)
        var snapshot=VaultSnapshot();snapshot.records=[record]
        let draft=RichDraft(entryID:record.id,path:[0,0],expectedDocument:raw,text:"UNSENT WRITING")
        snapshot.richDrafts=[draft];snapshot.conflicts=[record]
        snapshot.mediaUploads=[MediaUpload(id:String(repeating:"a",count:32),chunks:1,cipherBytes:42,plainBytes:1,name:"pending",mime:"text/plain")]
        snapshot.mediaCache=[MediaCache(id:String(repeating:"b",count:32),chunks:1,cipherBytes:42)]
        let before=snapshot
        let moved=try snapshot.reorderRichBlocks(expected:record,from:IndexSet([0,2]),to:14)
        XCTAssertEqual(snapshot.richDrafts,before.richDrafts);XCTAssertEqual(snapshot.mediaUploads,before.mediaUploads);XCTAssertEqual(snapshot.mediaCache,before.mediaCache);XCTAssertEqual(snapshot.conflicts,before.conflicts)
        XCTAssertThrowsError(try draft.applying(to:moved),"A retained old path must never edit another block after reorder")
    }
    func testEncryptedCommitFailureRetainsOldBytesAndRetryReopensWithSameKey() throws {
        let dir=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:dir)}
        let key=SymmetricKey(size:.bits256),disk=EncryptedSnapshotStore(directory:dir,namespace:"structure",key:key)
        let f=try fixture(),raw=String(decoding:try encoded(f["original"]!),as:UTF8.self)
        var snapshot=VaultSnapshot();snapshot.records=[entry(raw)];try disk.save(snapshot)
        let file=dir.appendingPathComponent("structure.vault"),before=try Data(contentsOf:file)
        var next=snapshot;_ = try next.reorderRichBlocks(expected:snapshot.records[0],from:IndexSet([0,2]),to:14)
        disk.prepareWriteForTesting={throw ChapterError.storage}
        XCTAssertThrowsError(try disk.save(next));XCTAssertEqual(try Data(contentsOf:file),before);XCTAssertEqual(try disk.load(),snapshot)
        disk.prepareWriteForTesting=nil;try disk.save(next)
        let reopened=EncryptedSnapshotStore(directory:dir,namespace:"structure",key:key);XCTAssertEqual(try reopened.load(),next)
        XCTAssertNil(try Data(contentsOf:file).range(of:Data("Public heading".utf8)))
    }
}
