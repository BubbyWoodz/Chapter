// SPDX-License-Identifier: AGPL-3.0-or-later
import XCTest
@testable import ChapterCore

final class InterviewTypesTests: XCTestCase {
    private func fixture() throws -> JSONValue {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "interview-types", withExtension: "json"))
        return try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
    }
    func testBodiesMatchTheWebInterviewTypeCodec() throws {
        let f = try fixture()
        XCTAssertEqual(InterviewTypes.builtins.map(\.slug), f["builtins"].array.map { $0["slug"].string! })
        XCTAssertEqual(InterviewTypes.builtins.first?.prompt, f["builtins"].array.first?["prompt"].string)
        let created = try InterviewTypes.newType(name: "Evening", intro: "One line", prompt: "Cover the evening.", id: "a" + String(repeating: "a", count: 31), clock: 1700000000000)
        XCTAssertEqual(JSONValue.object(created.body), f["wire"]["created"]["body"]); XCTAssertEqual(Double(created.clock), f["wire"]["created"]["lww_clock"].number)
        let seed = InterviewTypes.builtins[0]
        let fork = try InterviewTypes.fork(seed, name: "Mine", intro: "Intro", prompt: seed.prompt, id: String(repeating: "b", count: 32), clock: 1700000000001)
        XCTAssertEqual(JSONValue.object(fork.body), f["wire"]["fork"]["body"])
        let tomb = try created.deletingInterviewType(expected: created, now: Date(timeIntervalSince1970: 1700000000.002))
        XCTAssertTrue(tomb.deleted); XCTAssertEqual(JSONValue.object(tomb.body), f["wire"]["tombstone"]["body"]); XCTAssertEqual(Double(tomb.clock), f["wire"]["tombstone"]["lww_clock"].number)
    }
    func testEditsKeepUnknownFieldsAndSeedsRetireOnFork() throws {
        var record = try InterviewTypes.newType(name: "A", intro: "", prompt: "", id: "x", clock: 1700000000000)
        record.body["futureField"] = .bool(true); record.dirty = false
        let same = try record.editingInterviewType(expected: record, name: "A", intro: "", prompt: "")
        XCTAssertEqual(same, record, "No change writes nothing")
        let edited = try record.editingInterviewType(expected: record, name: "B", intro: "i", prompt: "p", now: Date(timeIntervalSince1970: 1800000000))
        XCTAssertEqual(edited.body["futureField"], .bool(true)); XCTAssertEqual(edited.body["name"], .string("B")); XCTAssertTrue(edited.dirty)
        XCTAssertEqual(edited.body["createdAt"], record.body["createdAt"]); XCTAssertEqual(edited.body["updatedAt"], .number(Double(edited.clock)))
        XCTAssertThrowsError(try edited.editingInterviewType(expected: record, name: "C", intro: "", prompt: ""), "Stale writes are rejected")
        let c = InterviewTypes.cleaned(name: " \u{00A0} ", intro: "  hi\n", prompt: "\tp ", untitled: "Untitled interview")
        XCTAssertEqual(c.name, "Untitled interview"); XCTAssertEqual(c.intro, "hi"); XCTAssertEqual(c.prompt, "p")
        let fork = try InterviewTypes.fork(InterviewTypes.builtins[1], name: "n", intro: "", prompt: "", id: "y", clock: 1700000000000, deleted: true)
        XCTAssertFalse(InterviewTypes.pristine(records: [fork]).contains(InterviewTypes.builtins[1]))
        XCTAssertEqual(InterviewTypes.pristine(records: [fork]).count, InterviewTypes.builtins.count - 1)
    }
}
