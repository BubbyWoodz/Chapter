// SPDX-License-Identifier: AGPL-3.0-or-later
import XCTest
@testable import ChapterCore

final class ChapterBadgesTests: XCTestCase {
    func testBadgesMatchTheWebStateBadges() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "badges", withExtension: "json"))
        let f = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
        XCTAssertEqual(ChapterBadges.order, f["order"].array.map { $0.string! })
        XCTAssertEqual(ChapterBadges.order.count, 8)
        XCTAssertEqual(ChapterBadges.seenKey("OWNER"), f["seenKey"].string)
        for c in f["evaluate"].array {
            let entries = c["entries"].array.map { e in
                ChapterBadges.Entry(id: e["id"].string!, deleted: e["deleted"] == .bool(true), createdAt: e["createdAt"].number!, bodyText: e["bodyText"].string!,
                                    bodyJson: e["bodyJson"].string, labels: e["labels"].array.map { $0.string! }, attachments: e["attachments"].array.count)
            }
            let earned = ChapterBadges.evaluate(entries, interviewTypeNames: c["types"].array.map { $0.string! })
            XCTAssertEqual(ChapterBadges.order.filter(earned.contains), c["earned"].array.map { $0.string! }, c["name"].string!)
        }
        for c in f["seen"].array {
            let got = ChapterBadges.loadSeen(c["raw"].string)
            if c["seen"] == .null { XCTAssertNil(got, c["raw"].string ?? "null") } else { XCTAssertEqual(got, Set(c["seen"].array.map { $0.string! })) }
        }
        for c in f["delta"].array {
            let r = ChapterBadges.catchUpOrDelta(seen: ChapterBadges.loadSeen(c["raw"].string), earned: Set(c["earned"].array.map { $0.string! }))
            XCTAssertEqual(r.seen, Set(c["seen"].array.map { $0.string! }))
            XCTAssertEqual(r.celebrate, c["celebrate"].array.map { $0.string! })
        }
        XCTAssertEqual(ChapterBadges.encodeSeen(["streak-7", "first-words", "bogus"]), "[\"first-words\",\"streak-7\"]")
        // Seeds named in the current language; a synced fork retires its seed, a tombstone hides the name.
        let fork = VaultRecord(id: "t", clock: 1, deleted: true, body: ["kind": .string("interviewType"), "builtin": .string(ChapterBadges.builtinInterviews[0].slug), "name": .string("Mine")])
        let names = ChapterBadges.interviewTypeNames([fork], name: { "N:" + $0 })
        XCTAssertEqual(names.count, ChapterBadges.builtinInterviews.count - 1)
        XCTAssertFalse(names.contains("Mine"))
    }
}
