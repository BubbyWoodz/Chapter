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
        // Authoring vector checked by the actual web schema/collector/preview.
        let source=VaultRecord(id:"fixture",clock:1,body:["kind":.string("entry"),"bodyJson":.string(raw)])
        let target=VaultRecord(id:"entry-target-2",clock:1,body:["kind":.string("entry"),"title":.string("Linked 📝 é")])
        let linked=try source.addingEntryLink(to:target,expected:raw,now:Date(timeIntervalSince1970:10))
        XCTAssertEqual(linked.linkedEntryIDs,["entry-target","entry-target-2"])
        if let output=ProcessInfo.processInfo.environment["CHAPTER_NATIVE_OUTPUT"] {try JSONEncoder().encode(["bodyJson":linked.body["bodyJson"]!.string!,"bodyText":linked.body["bodyText"]!.string!]).write(to:URL(fileURLWithPath:output+".entry-link-insert"))}
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
    func entry(_ id:String,title:String?,updated:Double,deleted:Bool=false,kind:String="entry")->VaultRecord {
        var body:[String:JSONValue]=["kind":.string(kind),"updatedAt":.number(updated)];if let title {body["title"] = .string(title)}
        return VaultRecord(id:id,clock:1,deleted:deleted,body:body)
    }
    func testLinkPickerMatchesOriginalWebFilterOrderingLimitAndUntitledFallback() throws {
        var state=VaultSnapshot()
        state.records=[entry("current",title:"Garden current",updated:99),entry("gone",title:"Garden gone",updated:98,deleted:true),entry("tpl",title:"Garden template",updated:97,kind:"template"),
                       entry("blank",title:"",updated:50),entry("none",title:nil,updated:49),entry("tie-a",title:"Garden tie",updated:10),entry("tie-b",title:"GARDEN tie",updated:10)]
        for i in 0..<10 {state.records.append(entry("g\(i)",title:"garden \(i)",updated:Double(i)))}
        XCTAssertEqual(state.entryLinkCandidates(excluding:"current",query:"  GARDEN \u{3000}").map(\.id),["tie-a","tie-b","g9","g8","g7","g6","g5","g4"])
        XCTAssertEqual(state.entryLinkCandidates(excluding:"current",query:"untitled").map(\.id),["blank","none"])
        XCTAssertEqual(state.entryLinkCandidates(excluding:"current",query:"").count,8)
        XCTAssertFalse(state.entryLinkCandidates(excluding:"current",query:"").contains{["current","gone","tpl"].contains($0.id)})
        // JS includes is code-unit exact: NFC query never matches an NFD title.
        state.records=[entry("nfd",title:"Cafe\u{0301}",updated:1),entry("nfc",title:"Caf\u{00E9}",updated:2)]
        XCTAssertEqual(state.entryLinkCandidates(excluding:"x",query:"caf\u{00E9}").map(\.id),["nfc"])
        XCTAssertEqual(state.entryLinkCandidates(excluding:"x",query:"cafe\u{0301}").map(\.id),["nfd"])
    }
    func testInsertedLinkIsExactOriginalWebNodeAndPreservesEveryExistingByte() throws {
        let original=#"{"type":"doc","attrs":{"future":[1,{"x":"é"}]},"content":[{"type":"paragraph","content":[{"type":"text","text":"Before","marks":[{"type":"futureMark","attrs":{"k":"v"}}]}]},{"type":"futureNode","attrs":{"keep":true}}]}"#
        let source=VaultRecord(id:"source",clock:5,body:["kind":.string("entry"),"title":.string("Source"),"bodyJson":.string(original),"futureField":.string("kept")])
        let target=entry("target-é",title:"Target 📝",updated:3)
        let next=try source.addingEntryLink(to:target,expected:original,now:Date(timeIntervalSince1970:100))
        let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
        let before=try JSONDecoder().decode(JSONValue.self,from:Data(original.utf8)),after=try JSONDecoder().decode(JSONValue.self,from:Data(next.body["bodyJson"]!.string!.utf8))
        guard case .array(let a)=before["content"],case .array(let b)=after["content"] else {return XCTFail("content")}
        XCTAssertEqual(b.count,a.count+1);XCTAssertEqual(try encoder.encode(Array(b.prefix(a.count))),try encoder.encode(a));XCTAssertEqual(try encoder.encode(after["attrs"]),try encoder.encode(before["attrs"]))
        let expected=#"{"content":[{"attrs":{"entryId":"target-é","label":"Target 📝"},"type":"entryLink"},{"text":" ","type":"text"}],"type":"paragraph"}"#
        XCTAssertEqual(String(decoding:try encoder.encode(b.last!),as:UTF8.self),expected)
        XCTAssertEqual(next.linkedEntryIDs,["target-é"]);XCTAssertEqual(next.body["futureField"]?.string,"kept");XCTAssertTrue(next.dirty);XCTAssertGreaterThan(next.clock,5)
        XCTAssertTrue(next.body["bodyText"]!.string!.hasSuffix("🔗 Target 📝"))
        XCTAssertEqual(try source.addingEntryLink(to:entry("blank",title:"",updated:1),expected:original).body["bodyJson"]?.string?.contains(#""label":"Untitled""#),true)
    }
    func testStaleSelfDeletedTemplateAndInvalidTargetsRefuseWithoutMutation() throws {
        let original=#"{"type":"doc","content":[]}"#
        let source=VaultRecord(id:"é",clock:5,body:["kind":.string("entry"),"bodyJson":.string(original)])
        let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys];let snapshot=try encoder.encode(source)
        XCTAssertThrowsError(try source.addingEntryLink(to:entry("t",title:"T",updated:1),expected:#"{"type":"doc","content":[{"type":"paragraph"}]}"#))
        // Canonically-equivalent expected bytes are still stale (exact CAS).
        let nfc=VaultRecord(id:"s",clock:1,body:["kind":.string("entry"),"bodyJson":.string(#"{"type":"doc","content":[{"type":"text","text":"é"}]}"#)])
        XCTAssertThrowsError(try nfc.addingEntryLink(to:entry("t",title:"T",updated:1),expected:#"{"type":"doc","content":[{"type":"text","text":"e\#u{0301}"}]}"#))
        for target in [entry("é",title:"Self",updated:1),entry("gone",title:"Gone",updated:1,deleted:true),entry("tpl",title:"Tpl",updated:1,kind:"template"),entry("",title:"Empty",updated:1),entry("bad\n",title:"Ctl",updated:1)] {
            XCTAssertThrowsError(try source.addingEntryLink(to:target,expected:original))
        }
        XCTAssertNoThrow(try source.addingEntryLink(to:entry("e\u{0301}",title:"Different bytes",updated:1),expected:original))
        let deletedSource=VaultRecord(id:"d",clock:1,deleted:true,body:["kind":.string("entry"),"bodyJson":.string(original)])
        XCTAssertThrowsError(try deletedSource.addingEntryLink(to:entry("t",title:"T",updated:1),expected:original))
        XCTAssertEqual(try encoder.encode(source),snapshot)
    }
}
