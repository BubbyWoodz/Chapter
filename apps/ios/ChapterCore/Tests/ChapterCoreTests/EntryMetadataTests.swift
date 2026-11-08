// SPDX-License-Identifier: AGPL-3.0-or-later
import XCTest
import CryptoKit
@testable import ChapterCore

final class EntryMetadataTests: XCTestCase {
    private func entry() throws -> VaultRecord {
        let file = try XCTUnwrap(Bundle.module.url(forResource:"rich-document",withExtension:"json"))
        let fixture = try JSONDecoder().decode([String:JSONValue].self,from:Data(contentsOf:file))
        let document = String(decoding:try JSONEncoder().encode(fixture["original"]!),as:UTF8.self)
        return VaultRecord(id:"native-entry-metadata",clock:12,body:["title":.string("Original title"),"journalId":.string("original"),"bodyJson":.string(document),"bodyText":fixture["originalPreview"]!,"labels":.array([.string("ImportedCase"),.string("old, label")]),"createdAt":.number(1),"unknownFuture":.object(["preserve":.bool(true)])],dirty:true)
    }
    func testMetadataPatchesPreserveEveryOriginalRichByteAndReverseCiphertext() throws {
        let original = try entry()
        let changed = try original.editingEntryMetadata(expected:original,title:"Native metadata",date:Date(timeIntervalSince1970:1700000000),labels:["travel, friends","ImportedCase"],now:Date(timeIntervalSince1970:1700000001))
        for key in ["bodyJson","bodyText","journalId","unknownFuture"] { XCTAssertEqual(changed.body[key],original.body[key]) }
        XCTAssertEqual(changed.id,original.id); XCTAssertEqual(changed.clock,1700000001000); XCTAssertTrue(changed.dirty)
        XCTAssertEqual(changed.body["createdAt"],.number(1700000000000)); XCTAssertEqual(changed.labels,["travel, friends","ImportedCase"])
        if let path = ProcessInfo.processInfo.environment["CHAPTER_NATIVE_OUTPUT"] {
            let identity = try VaultIdentity(seed:RecoveryPhrase.seed("legal winner thank year wave sausage worth useful legal winner thank yellow"))
            let cipher = try VaultCipher.sealRecord(JSONEncoder().encode(changed.body),key:identity.dataKey,id:changed.id)
            try JSONEncoder().encode(["id":changed.id,"record":cipher.base64EncodedString()]).write(to:URL(fileURLWithPath:path+".entry-metadata"))
        }
    }
    func testUnknownLabelsStayOpaqueAndNoOpAcknowledgementDoesNotAdvance() throws {
        var original = try entry(); original.body["labels"] = .object(["future":.array([.bool(true)])])
        XCTAssertNil(original.editableEntryLabels)
        let titleOnly = try original.editingEntryMetadata(expected:original,title:"Title only")
        XCTAssertEqual(titleOnly.body["labels"],original.body["labels"])
        XCTAssertThrowsError(try original.editingEntryMetadata(expected:original,labels:[]))
        var acknowledged = original; acknowledged.dirty = false
        XCTAssertEqual(try acknowledged.editingEntryMetadata(expected:original,title:original.title),acknowledged)
        original.body["labels"] = .array([.string("Keep"),.object(["future":.bool(true)])])
        XCTAssertNil(original.editableEntryLabels); XCTAssertThrowsError(try original.editingEntryMetadata(expected:original,labels:["Keep"]))
    }
    func testStaleDeletedKindClockAndInvalidDateRefuseWithoutMutation() throws {
        let original = try entry(); var changed = original; changed.clock += 1
        XCTAssertThrowsError(try changed.editingEntryMetadata(expected:original,title:"Overwrite"))
        changed = original; changed.body["opaque"] = .bool(true)
        XCTAssertThrowsError(try changed.editingEntryMetadata(expected:original,title:"Overwrite"))
        changed = original; changed.deleted = true; XCTAssertThrowsError(try changed.editingEntryMetadata(expected:changed,title:"Resurrect"))
        changed = original; changed.body["kind"] = .string("journal"); XCTAssertThrowsError(try changed.editingEntryMetadata(expected:changed,title:"Wrong kind"))
        changed = original; changed.clock = ProtocolNumbers.maxWireInteger; XCTAssertThrowsError(try changed.editingEntryMetadata(expected:changed,title:"Overflow"))
        for seconds in [Double.infinity,Double.nan,1e100,-1e100] { XCTAssertThrowsError(try original.editingEntryMetadata(expected:original,date:Date(timeIntervalSince1970:seconds))) }
        XCTAssertEqual(original.body["title"],.string("Original title"))
    }
    func testEncryptedMetadataFailureKeepsPreviousBytesDraftsAndMediaThenRetries() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:directory) }
        let namespace = "public-rich-metadata-fault", key = SymmetricKey(data:Data(repeating:23,count:32))
        let store = EncryptedSnapshotStore(directory:directory,namespace:namespace,key:key)
        var before = VaultSnapshot(); before.records = [try entry()]
        before.richDrafts = [RichDraft(entryID:before.records[0].id,path:[0,0],expectedDocument:before.records[0].body["bodyJson"]!.string!,text:"Pending original draft")]
        before.mediaUploads = [MediaUpload(id:String(repeating:"a",count:32),chunks:1,cipherBytes:42,plainBytes:1,name:"Pending original file",mime:"application/octet-stream")]
        try store.save(before)
        let path = directory.appendingPathComponent(namespace+".vault"), previousBytes = try Data(contentsOf:directory.appendingPathComponent(namespace+".vault"))
        var next = before; next.records[0] = try before.records[0].editingEntryMetadata(expected:before.records[0],title:"PRIVATE-METADATA-UPDATE")
        store.prepareWriteForTesting = { throw NSError(domain:"public-metadata-disk-fault",code:1) }
        XCTAssertThrowsError(try store.save(next)); XCTAssertEqual(try Data(contentsOf:path),previousBytes)
        XCTAssertEqual(try store.load(),before)
        store.prepareWriteForTesting = nil; try store.save(next)
        let reopened = try EncryptedSnapshotStore(directory:directory,namespace:namespace,key:key).load()
        XCTAssertEqual(reopened,next); XCTAssertEqual(reopened.richDrafts,before.richDrafts); XCTAssertEqual(reopened.mediaUploads,before.mediaUploads)
        XCTAssertEqual(reopened.records[0].body["bodyJson"],before.records[0].body["bodyJson"])
        XCTAssertNil(try Data(contentsOf:path).range(of:Data("PRIVATE-METADATA-UPDATE".utf8)))
        XCTAssertThrowsError(try EncryptedSnapshotStore(directory:directory,namespace:namespace,key:SymmetricKey(data:Data(repeating:24,count:32))).load())
    }
    func testPlainWritingDoesNotSplitUntouchedCommaLabelsOrEraseFutureSchemas() throws {
        var original = try entry(); original.body["labels"] = .array([.string("travel, friends"),.string("ImportedCase")])
        XCTAssertEqual(try EntryLabels.plainFieldValue(original.labels.joined(separator:", "),original:original),original.body["labels"])
        XCTAssertEqual(try EntryLabels.plainFieldValue(" WORK   LIFE, Travel , work life, ",original:original),.array([.string("work life"),.string("travel")]))
        original.body["labels"] = .object(["future":.bool(true)])
        XCTAssertEqual(try EntryLabels.plainFieldValue(original.labels.joined(separator:", "),original:original),original.body["labels"])
        XCTAssertThrowsError(try EntryLabels.plainFieldValue("replace future",original:original))
        original.body.removeValue(forKey:"labels")
        XCTAssertNil(try EntryLabels.plainFieldValue("",original:original))
        XCTAssertEqual(try EntryLabels.plainFieldValue(" ",original:nil),.array([]))
    }
    func testImportedUnicodeLabelsRemainDistinctLikeOriginalWeb() throws {
        let first = "caf\u{00E9}", second = "cafe\u{0301}"
        XCTAssertEqual(first,second,"This fixture must expose Swift canonical equality")
        XCTAssertFalse(EntryLabels.contains([first],second)); XCTAssertTrue(EntryLabels.contains([first],first))
        XCTAssertEqual(EntryLabels.unique([first,second,first]).count,2)
        var original = try entry(); original.body["labels"] = .array([.string(first)]); original.body["title"] = .string(first)
        let changed = try original.editingEntryMetadata(expected:original,title:second,labels:[second])
        XCTAssertGreaterThan(changed.clock,original.clock)
        XCTAssertEqual(Array(try XCTUnwrap(changed.body["title"]?.string).utf8),Array(second.utf8))
        XCTAssertEqual(Array(try XCTUnwrap(changed.editableEntryLabels?.first).utf8),Array(second.utf8))
        XCTAssertEqual(changed.body["bodyJson"],original.body["bodyJson"])
    }
    func testLabelNormalizationUsesActualOriginalWebGoldenCases() throws {
        let file = try XCTUnwrap(Bundle.module.url(forResource:"entry-labels",withExtension:"json"))
        let cases = try JSONDecoder().decode([[String:String]].self,from:Data(contentsOf:file))
        for item in cases { XCTAssertEqual(Array(EntryLabels.normalized(try XCTUnwrap(item["input"])).utf8),Array(try XCTUnwrap(item["expected"]).utf8)) }
    }
}
