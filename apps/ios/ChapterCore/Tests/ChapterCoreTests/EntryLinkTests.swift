// SPDX-License-Identifier: AGPL-3.0-or-later
import XCTest
@testable import ChapterCore
final class EntryLinkTests:XCTestCase {
    func record(_ id:String,_ target:String,updated:Double=1,deleted:Bool=false,kind:String="entry") throws -> VaultRecord {
        let doc:JSONValue = .object(["type":.string("doc"),"content":.array([.object(["type":.string("paragraph"),"content":.array([.object(["type":.string("entryLink"),"attrs":.object(["entryId":.string(target),"label":.string("Stored label")])])])])])])
        return VaultRecord(id:id,clock:1,deleted:deleted,body:["kind":.string(kind),"updatedAt":.number(updated),"bodyJson":.string(String(decoding:try JSONEncoder().encode(doc),as:UTF8.self))])
    }
    func testOriginalWebFixtureLinksAndDocumentOrderAreUnchanged() throws {
        let url=try XCTUnwrap(Bundle.module.url(forResource:"rich-document",withExtension:"json"))
        let fixture=try JSONDecoder().decode([String:JSONValue].self,from:Data(contentsOf:url))
        let raw=String(decoding:try JSONEncoder().encode(fixture["original"]!),as:UTF8.self)
        let value=VaultRecord(id:"fixture",clock:1,body:["bodyJson":.string(raw)])
        XCTAssertEqual(value.linkedEntryIDs,["entry-target"]);XCTAssertEqual(value.body["bodyJson"]?.string,raw)
        if let output=ProcessInfo.processInfo.environment["CHAPTER_NATIVE_OUTPUT"] {try JSONEncoder().encode(["ids":value.linkedEntryIDs]).write(to:URL(fileURLWithPath:output+".entry-links"))}
    }
    func testLocalRouteRoundtripsExactUnicodeAndNeverTurnsIDIntoExternalHost() throws {
        for id in ["entry-target","https://untrusted.invalid/?x=y#z","../another/entry?x=1&y=2","é","e\u{0301}","空 📝 +%"] {
            let url=try XCTUnwrap(EntryLinkRoute.url(for:id));XCTAssertEqual(url.host,"open");XCTAssertEqual(url.scheme,"chapter-entry")
            XCTAssertEqual(Data(try XCTUnwrap(EntryLinkRoute.entryID(from:url)).utf8),Data(id.utf8))
        }
        for id in ["","control\n",String(repeating:"x",count:513)] {XCTAssertNil(EntryLinkRoute.url(for:id))}
        for raw in ["https://open?id=entry","chapter-entry://evil?id=entry","chapter-entry://open?id=entry&id=other","chapter-entry://open/path?id=entry","chapter-entry://user@open?id=entry","chapter-entry://open?id=entry#fragment"] {XCTAssertNil(EntryLinkRoute.entryID(from:try XCTUnwrap(URL(string:raw))))}
    }
    func testBacklinksMatchOriginalSelfDeletedKindAndUpdatedOrderingWithoutUnicodeCollapse() throws {
        var state=VaultSnapshot();let old=try record("old","é",updated:2),recent=try record("recent","é",updated:9)
        state.records=[try record("é","é"),old,recent,try record("deleted","é",deleted:true),try record("metadata","é",kind:"template"),try record("different","e\u{0301}")]
        let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys];let before=try encoder.encode(state);XCTAssertEqual(state.backlinks(to:"é"),[recent,old]);XCTAssertEqual(state.backlinks(to:"e\u{0301}").map(\.id),["different"])
        XCTAssertEqual(try encoder.encode(state),before)
    }
    func testDuplicateAndOpaqueDescendantLinksMatchOriginalCollectorButInvalidContentFailsClosed() throws {
        let value=VaultRecord(id:"x",clock:1,body:["bodyJson":.string(#"{"type":"doc","content":[{"type":"futureNode","content":[{"type":"entryLink","attrs":{"entryId":"one"}},{"type":"entryLink","attrs":{"entryId":"one"}},{"type":"entryLink","attrs":{"entryId":""}},{"type":"entryLink","attrs":{"entryId":7}}]}]}"#)])
        XCTAssertEqual(value.linkedEntryIDs,["one","one"]);XCTAssertEqual(value.uniqueLinkedEntryIDs,["one"])
        for raw in ["invalid",#"{"type":"doc","content":{}}"#] {XCTAssertTrue(VaultRecord(id:"bad",clock:1,body:["bodyJson":.string(raw)]).linkedEntryIDs.isEmpty)}
    }
}
