// SPDX-License-Identifier: AGPL-3.0-or-later
import XCTest
@testable import ChapterCore

final class EntryTemplateTests: XCTestCase {
    func testDefaultTitleEqualsOriginalWebAcrossTimeZonesAndDST() throws {
        let cases = try JSONDecoder().decode([JSONValue].self, from: Data(contentsOf: try XCTUnwrap(Bundle.module.url(forResource:"entry-titles",withExtension:"json")))); XCTAssertEqual(cases.count, 16)
        for c in cases {
            let zone = try XCTUnwrap(TimeZone(identifier: c["tz"].string ?? ""))
            XCTAssertEqual(EntryTemplates.defaultTitle(milliseconds: c["ms"].number ?? -1, timeZone: zone), c["title"].string, "\(c)")
        }
    }
    func testNewEntryCopiesExactTemplateStringsLikeOriginalCreateEntry() throws {
        // Deliberately non-canonical JSON spacing, NFD text and an unknown node: copied byte-for-byte.
        let json = "{\"type\": \"doc\",\"content\":[{\"type\":\"futureNode\",\"attrs\":{\"x\":1}},{\"type\":\"paragraph\",\"content\":[{\"type\":\"text\",\"text\":\"Cafe\u{0301}\"}]}]}"
        let template = VaultRecord(id: "tpl", clock: 3, body: ["kind": .string("template"), "name": .string("Weekly"), "bodyJson": .string(json), "bodyText": .string("Cafe\u{0301}"), "builtin": .string("weekly")])
        let entry = try EntryTemplates.newEntry(from: template, journalID: "j-1", id: "new-id", clock: 1773536400000, timeZone: TimeZone(identifier: "America/Los_Angeles")!)
        XCTAssertEqual(entry.kind, "entry"); XCTAssertNil(entry.body["kind"]); XCTAssertTrue(entry.dirty); XCTAssertEqual(entry.clock, 1773536400000)
        XCTAssertEqual(Data(entry.body["bodyJson"]!.string!.utf8), Data(json.utf8)); XCTAssertEqual(Data(entry.body["bodyText"]!.string!.utf8), Data("Cafe\u{0301}".utf8))
        XCTAssertEqual(entry.body["title"]?.string, "2026-03-14 18:00:00"); XCTAssertEqual(entry.body["labels"], .array([])); XCTAssertEqual(entry.body["journalId"]?.string, "j-1")
        XCTAssertEqual(Set(entry.body.keys), ["journalId", "title", "bodyText", "bodyJson", "labels", "createdAt", "updatedAt"], "Only the original entry codec fields; no template name/builtin leak")
        let textOnly = try EntryTemplates.newEntry(from: VaultRecord(id: "t2", clock: 1, body: ["kind": .string("template"), "name": .string("")]), journalID: "j", id: "n", clock: 5)
        XCTAssertNil(textOnly.body["bodyJson"]); XCTAssertEqual(textOnly.body["bodyText"]?.string, "")
        XCTAssertEqual(EntryTemplates.name(VaultRecord(id: "t2", clock: 1, body: ["kind": .string("template"), "name": .string("")])), "Untitled template")
    }
    func testDeletedNonTemplateAndMalformedFieldsRefuse() {
        let ok: [String: JSONValue] = ["kind": .string("template"), "name": .string("x")]
        XCTAssertThrowsError(try EntryTemplates.newEntry(from: VaultRecord(id: "t", clock: 1, deleted: true, body: ok), journalID: "j", id: "n", clock: 1))
        XCTAssertThrowsError(try EntryTemplates.newEntry(from: VaultRecord(id: "t", clock: 1, body: ["name": .string("entry")]), journalID: "j", id: "n", clock: 1))
        var bad = ok; bad["bodyJson"] = .number(1)
        XCTAssertThrowsError(try EntryTemplates.newEntry(from: VaultRecord(id: "t", clock: 1, body: bad), journalID: "j", id: "n", clock: 1))
        XCTAssertThrowsError(try EntryTemplates.newEntry(from: VaultRecord(id: "t", clock: 1, body: ok), journalID: "", id: "n", clock: 1))
    }
}
