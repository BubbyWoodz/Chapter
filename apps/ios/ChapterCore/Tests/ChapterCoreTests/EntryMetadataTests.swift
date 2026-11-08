// SPDX-License-Identifier: AGPL-3.0-or-later
import XCTest
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
    func testLabelNormalizationUsesActualOriginalWebGoldenCases() throws {
        let file = try XCTUnwrap(Bundle.module.url(forResource:"entry-labels",withExtension:"json"))
        let cases = try JSONDecoder().decode([[String:String]].self,from:Data(contentsOf:file))
        for item in cases { XCTAssertEqual(EntryLabels.normalized(try XCTUnwrap(item["input"])),item["expected"]) }
    }
}
