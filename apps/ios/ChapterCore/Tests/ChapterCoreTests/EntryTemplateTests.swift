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
    func testCreateRenameDeleteMatchOriginalWebTemplateManager() throws {
        let created = try EntryTemplates.newTemplate(name: "\u{00A0} Morning pages\u{3000}", text: "Gratitude\n\nCafe\u{0301} plan", id: "tpl-new", clock: 1773536400000)
        XCTAssertEqual(created.kind, "template"); XCTAssertTrue(created.dirty); XCTAssertFalse(created.deleted)
        XCTAssertEqual(created.body["name"]?.string, "Morning pages", "ECMAScript trim like name.trim()")
        XCTAssertEqual(Set(created.body.keys), ["kind", "name", "bodyText", "bodyJson", "createdAt", "updatedAt"], "Exactly the original templateCodec fields; builtin stays absent")
        XCTAssertEqual(created.body["createdAt"], .number(1773536400000)); XCTAssertEqual(created.body["updatedAt"], .number(1773536400000))
        XCTAssertEqual(Data(created.body["bodyText"]!.string!.utf8), Data(try RichDocument(json: created.body["bodyJson"]!.string!).plainText.utf8))
        if let output = ProcessInfo.processInfo.environment["CHAPTER_NATIVE_OUTPUT"] { try JSONEncoder().encode(created.body).write(to: URL(fileURLWithPath: output + ".template-authoring")) }
        let untouched = try EntryTemplates.newTemplate(name: "  ", text: "", id: "tpl-empty", clock: 5)
        XCTAssertEqual(untouched.body["name"]?.string, "Untitled template"); XCTAssertNil(untouched.body["bodyJson"]); XCTAssertEqual(untouched.body["bodyText"]?.string, "")
        XCTAssertThrowsError(try EntryTemplates.newTemplate(name: "x", text: "", id: "", clock: 5))
        // Synced built-in with odd JSON spacing, NFD text and an unknown field: rename keeps every byte but the name.
        let json = "{\"type\": \"doc\",\"content\":[{\"type\":\"futureNode\"}]}"
        let synced = VaultRecord(id: "tpl", clock: 10, body: ["kind": .string("template"), "name": .string("Weekly"), "bodyJson": .string(json), "bodyText": .string("Cafe\u{0301}"), "builtin": .string("weekly"), "future": .object(["keep": .bool(true)]), "createdAt": .number(1), "updatedAt": .number(10)])
        let renamed = try synced.renamingTemplate(expected: synced, name: " Weekly review ", now: Date(timeIntervalSince1970: 1773536400))
        XCTAssertEqual(renamed.body["name"]?.string, "Weekly review"); XCTAssertEqual(renamed.clock, 1773536400000); XCTAssertEqual(renamed.body["updatedAt"], .number(1773536400000)); XCTAssertTrue(renamed.dirty)
        for key in ["bodyJson", "bodyText", "builtin", "future", "createdAt"] { XCTAssertEqual(renamed.body[key], synced.body[key], key) }
        XCTAssertEqual(Data(renamed.body["bodyText"]!.string!.utf8), Data("Cafe\u{0301}".utf8))
        XCTAssertEqual(try synced.renamingTemplate(expected: synced, name: "Weekly"), synced, "No-op rename must not advance the clock")
        let fixed = Date(timeIntervalSince1970: 1773536400) // one instant for both, so only the name rule is compared
        XCTAssertEqual(try synced.renamingTemplate(expected: synced, name: "", now: fixed), try synced.renamingTemplate(expected: synced, name: "Untitled template", now: fixed))
        var stale = synced; stale.body["name"] = .string("Other device")
        XCTAssertThrowsError(try stale.renamingTemplate(expected: synced, name: "x"), "Stale editor value must refuse, not overwrite")
        let deleted = try synced.deletingTemplate(expected: synced, now: Date(timeIntervalSince1970: 1773536400))
        XCTAssertTrue(deleted.deleted); XCTAssertTrue(deleted.dirty); XCTAssertEqual(deleted.clock, 1773536400000)
        for key in ["name", "bodyJson", "bodyText", "builtin", "future", "createdAt"] { XCTAssertEqual(deleted.body[key], synced.body[key], key) }
        XCTAssertThrowsError(try deleted.deletingTemplate(expected: deleted)); XCTAssertThrowsError(try deleted.renamingTemplate(expected: deleted, name: "x"))
        let entry = VaultRecord(id: "e", clock: 1, body: ["title": .string("x")])
        XCTAssertThrowsError(try entry.deletingTemplate(expected: entry)); XCTAssertThrowsError(try entry.renamingTemplate(expected: entry, name: "x"))
    }
    func testBuiltinSeedsMatchOriginalWebAndRetireOrForkLikeSupersedeAndMutateSeeded() throws {
        let seeds = BuiltinTemplates.bundled
        XCTAssertEqual(seeds.map(\.slug), ["daily", "gratitude", "dream", "experiment", "study", "weekly"])
        XCTAssertEqual(seeds.first?.name, "Daily reflection")
        for seed in seeds { XCTAssertEqual(try RichDocument(json: seed.bodyJson).plainText, seed.bodyText, "Native preview text must equal the web docToText for \(seed.slug)") }
        let weekly = try XCTUnwrap(seeds.first { $0.slug == "weekly" })
        let entry = try EntryTemplates.newEntry(from: weekly.seedRecord, journalID: "j", id: "n", clock: 7)
        XCTAssertEqual(Data(entry.body["bodyJson"]!.string!.utf8), Data(weekly.bodyJson.utf8)); XCTAssertNil(entry.body["builtin"])
        let records = [
            VaultRecord(id: "a", clock: 2, deleted: true, body: ["kind": .string("template"), "builtin": .string("daily")]),
            VaultRecord(id: "b", clock: 2, body: ["kind": .string("template"), "builtin": .string("weekly"), "name": .string("Mine")]),
            VaultRecord(id: "c", clock: 2, body: ["builtin": .string("dream"), "title": .string("an entry, not a template")]),
        ]
        XCTAssertEqual(BuiltinTemplates.pristine(seeds, records: records).map(\.slug), ["gratitude", "dream", "experiment", "study"], "Live and tombstoned synced copies retire the seed; other kinds do not")
        let renamed = try BuiltinTemplates.fork(weekly, id: "f1", clock: 1773536400000, name: "  My week ")
        XCTAssertEqual(renamed.body["name"]?.string, "My week"); XCTAssertEqual(renamed.body["builtin"]?.string, "weekly"); XCTAssertFalse(renamed.deleted); XCTAssertTrue(renamed.dirty)
        XCTAssertEqual(Set(renamed.body.keys), ["kind", "name", "bodyText", "bodyJson", "builtin", "createdAt", "updatedAt"])
        XCTAssertEqual(Data(renamed.body["bodyJson"]!.string!.utf8), Data(weekly.bodyJson.utf8))
        let tomb = try BuiltinTemplates.fork(weekly, id: "f2", clock: 5, deleted: true)
        XCTAssertTrue(tomb.deleted); XCTAssertEqual(tomb.body["name"]?.string, "Weekly review"); XCTAssertEqual(tomb.body["builtin"]?.string, "weekly")
        XCTAssertEqual(BuiltinTemplates.pristine(seeds, records: [tomb]).count, 5)
        XCTAssertThrowsError(try BuiltinTemplates.fork(weekly, id: "", clock: 5))
        XCTAssertThrowsError(try BuiltinTemplates.load(from: Data("[]".utf8)))
        XCTAssertThrowsError(try BuiltinTemplates.load(from: Data(#"[{"slug":"a","name":"","bodyJson":"","bodyText":""},{"slug":"a","name":"","bodyJson":"","bodyText":""}]"#.utf8)))
    }
}
