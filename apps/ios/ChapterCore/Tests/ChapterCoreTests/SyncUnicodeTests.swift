// SPDX-License-Identifier: AGPL-3.0-or-later
import XCTest
import CryptoKit
@testable import ChapterCore

final class SyncUnicodeTests: XCTestCase {
    func record(_ value: String, clock: Int64 = 1, dirty: Bool = true) -> VaultRecord {
        VaultRecord(id:"unicode-sync",clock:clock,body:["bodyText":.string(value),"future":.object(["labels":.array([.string(value)])])],dirty:dirty)
    }
    func bytes<T:Encodable>(_ value:T) throws -> Data {
        let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys];return try encoder.encode(value)
    }
    func testCanonicalEquivalenceCannotAcknowledgeInflightEdit() {
        let sent=record("é"),changed=record("e\u{0301}")
        XCTAssertEqual(sent.text,changed.text);XCTAssertNotEqual(Data(sent.text.utf8),Data(changed.text.utf8))
        XCTAssertNotEqual(sent,changed);XCTAssertFalse(sent.hasSamePayload(as:changed))
        var state=VaultSnapshot();state.records=[changed];state.acknowledge(sent)
        XCTAssertTrue(state.records[0].dirty);state.acknowledge(changed);XCTAssertFalse(state.records[0].dirty)
    }
    func testEqualClockPullKeepsBothByteDistinctVersionsEvenWhenLocalClean() {
        for dirty in [true,false] {
            let local=record("é",dirty:dirty),remote=record("e\u{0301}",dirty:false)
            var state=VaultSnapshot();state.records=[local];state.merge(remote);state.merge(remote)
            XCTAssertEqual(state.records,[local]);XCTAssertEqual(state.conflicts,[remote])
            XCTAssertEqual(state.records[0].dirty,dirty)
        }
    }
    func testNewerRemotePreservesEveryUnsyncedCanonicalVersionWithoutDuplicateRecovery() {
        let original=record("é"),second=record("e\u{0301}"),remote=record("server",clock:2,dirty:false)
        var state=VaultSnapshot();state.conflicts=[original];state.records=[second];state.merge(remote)
        XCTAssertEqual(state.records,[remote]);XCTAssertEqual(state.conflicts,[original,second])
        state.records=[second];state.merge(remote);XCTAssertEqual(state.conflicts.count,2)
    }
    func testExactPayloadAcknowledgesRegardlessOfDictionaryInsertionOrderOrDeliveryFlag() {
        let sent=record("é");var remote=sent;remote.dirty=false
        remote.body=[:];remote.body["future"]=sent.body["future"];remote.body["bodyText"]=sent.body["bodyText"]
        XCTAssertTrue(sent.hasSamePayload(as:remote));var state=VaultSnapshot();state.records=[sent]
        state.merge(remote);XCTAssertFalse(state.records[0].dirty);XCTAssertTrue(state.conflicts.isEmpty)
        var deleted=sent;deleted.deleted=true;state.records=[deleted];state.acknowledge(sent);XCTAssertTrue(state.records[0].dirty)
        var invalid=sent;invalid.body["nonfinite"] = .number(.nan)
        XCTAssertFalse(invalid.hasSamePayload(as:invalid));state.records=[invalid];state.acknowledge(invalid);XCTAssertTrue(state.records[0].dirty)
    }
    func testOpaqueNestedUnicodeAndObjectKeySpellingAreNotCollapsed() {
        var a=record("same"),b=a
        a.body["opaque"] = .object(["é":.string("same")]);b.body["opaque"] = .object(["e\u{0301}":.string("same")])
        XCTAssertFalse(a.hasSamePayload(as:b));var state=VaultSnapshot();state.records=[a];state.acknowledge(b);XCTAssertTrue(state.records[0].dirty)
    }
    func testNotebookUnicodeOnlyRenameIsAnActualEditAndDeletionRetainsBothVersions() throws {
        let notebook=VaultRecord(id:"journal",clock:1,body:["kind":.string("journal"),"journalId":.string("j"),"name":.string("é")])
        let renamed=try notebook.editingJournal(expected:notebook,name:"e\u{0301}",now:Date(timeIntervalSince1970:1))
        XCTAssertTrue(renamed.dirty);XCTAssertEqual(Data(renamed.title.utf8),Data("e\u{0301}".utf8));XCTAssertGreaterThan(renamed.clock,1)
        let original=record("é"),changed=record("e\u{0301}")
        var state=VaultSnapshot();state.records=[changed];state.conflicts=[original]
        try state.deleteEntryPreservingRecovery(expected:changed)
        XCTAssertEqual(state.conflicts,[original,changed])
    }
    func testPlainEditorAndOpaqueFormattingCannotSilentlyNormalizeOriginalJSON() throws {
        let nfc="é",nfd="e\u{0301}"
        var plain=VaultRecord(id:"plain",clock:1,body:["chapterNativePlain":.bool(true),"bodyText":.string(nfc),"bodyJson":.string(try VaultRecord.plainDocument(nfc))])
        XCTAssertTrue(plain.editablePlainText);plain.body["bodyJson"] = .string(try VaultRecord.plainDocument(nfd))
        XCTAssertFalse(plain.editablePlainText,"A plain editor must not flatten a byte-distinct original document")
        let raw:JSONValue = .object(["type":.string("doc"),"content":.array([.object(["type":.string("paragraph"),"content":.array([.object(["type":.string("text"),"text":.string("same"),"marks":.array([.object(["type":.string("future"),"attrs":.object(["token":.string(nfc)])])])])])])])])
        var doc=try RichDocument(json:String(decoding:try bytes(raw),as:UTF8.self));let before=try bytes(doc.root)
        XCTAssertThrowsError(try doc.replaceText(at:[0,0],with:"edited",marks:[.object(["type":.string("future"),"attrs":.object(["token":.string(nfd)])])]))
        XCTAssertEqual(try bytes(doc.root),before)
    }
    func testEncryptedConflictAndAcknowledgementFaultCannotAdvanceCursorOrLoseOriginalBytes() throws {
        let dir=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:dir)}
        let key=SymmetricKey(size:.bits256),disk=EncryptedSnapshotStore(directory:dir,namespace:"unicode",key:key)
        var before=VaultSnapshot();before.records=[record("e\u{0301}")];before.cursor=7;try disk.save(before)
        let file=dir.appendingPathComponent("unicode.vault"),old=try Data(contentsOf:file)
        var next=before;next.acknowledge(record("é"));next.merge(record("é",dirty:false));next.cursor=8
        disk.prepareWriteForTesting={throw ChapterError.storage};XCTAssertThrowsError(try disk.save(next))
        XCTAssertEqual(try Data(contentsOf:file),old);XCTAssertEqual(try disk.load(),before)
        disk.prepareWriteForTesting=nil;try disk.save(next)
        let restored=try EncryptedSnapshotStore(directory:dir,namespace:"unicode",key:key).load()
        XCTAssertTrue(restored.records[0].dirty);XCTAssertEqual(try bytes(restored.records[0]),try bytes(before.records[0]))
        XCTAssertEqual(restored.conflicts.count,1);XCTAssertEqual(restored.cursor,8)
        var acknowledged=restored;acknowledged.acknowledge(restored.records[0]);try disk.save(acknowledged)
        XCTAssertFalse(try disk.load().records[0].dirty);XCTAssertEqual(try disk.load().conflicts,restored.conflicts)
    }
}
