// SPDX-License-Identifier: AGPL-3.0-or-later
import XCTest
@testable import ChapterCore

final class ChapterStatsTests: XCTestCase {
    func testWritingStatsEqualTheWebStatsModule() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "writing-stats", withExtension: "json", subdirectory: "Fixtures") ?? Bundle.module.url(forResource: "writing-stats", withExtension: "json"))
        let f = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
        let entries = f["entries"].array.map { ChapterStats.Item(id: $0["id"].string!, createdAt: $0["createdAt"].number!, bodyText: $0["bodyText"].string!) }
        for c in f["wordCounts"].array { XCTAssertEqual(ChapterStats.wordCount(c["text"].string!), Int(c["n"].number!), c["text"].string!.debugDescription) }
        XCTAssertEqual(ChapterStats.totalWords(entries), Int(f["totalWords"].number!))
        XCTAssertEqual(ChapterStats.journaledDays(entries), Int(f["journaledDays"].number!))
        XCTAssertEqual(ChapterStats.longestStreak(entries), Int(f["longestStreak"].number!))
        for c in f["streaks"].array { XCTAssertEqual(ChapterStats.dayStreak(entries, now: c["now"].number!), Int(c["n"].number!), "\(c["now"].number!)") }
        for c in f["monthWords"].array { XCTAssertEqual(ChapterStats.monthWords(entries, year: Int(c["year"].number!), month: Int(c["month"].number!)), Int(c["n"].number!)) }
        for c in f["compact"].array { XCTAssertEqual(ChapterStats.compactCount(Int(c["n"].number!)), c["out"].string, "\(c["n"].number!)") }
        for c in f["onThisDay"].array { XCTAssertEqual(ChapterStats.onThisDay(entries, month: Int(c["month"].number!), day: Int(c["day"].number!), year: Int(c["year"].number!)).map(\.id), c["ids"].array.map { $0.string! }) }
        for c in f["daily"].array { XCTAssertEqual(ChapterStats.dailyCounts(entries, now: c["now"].number!, weeks: Int(c["weeks"].number!)), c["counts"].array.map { Int($0.number!) }, "\(c["now"].number!)") }
        for c in f["accents"].array {
            let palette = c["palette"].string!, dark = c["dark"] == .bool(true)
            func rgb(_ t: (r: Int, g: Int, b: Int, a: Double)?) -> String { "rgb(\(t!.r),\(t!.g),\(t!.b))" }
            func rgba(_ t: (r: Int, g: Int, b: Int, a: Double)?) -> String { "rgba(\(t!.r),\(t!.g),\(t!.b),\(t!.a))" }
            XCTAssertEqual(rgb(AppearanceCatalog.accentToken("accent-ink", palette: palette, dark: dark)), c["ink"].string, palette)
            XCTAssertEqual(rgba(AppearanceCatalog.accentToken("accent-soft", palette: palette, dark: dark)), c["soft"].string, palette)
            XCTAssertEqual(rgba(AppearanceCatalog.accentToken("accent-line", palette: palette, dark: dark)), c["line"].string, palette)
        }
        XCTAssertGreaterThanOrEqual(f["accents"].array.count, 12)
        // Exact JavaScript toFixed ties round up (1.25 → "1.3"), unlike printf's half-even.
        XCTAssertEqual(ChapterStats.compactCount(1250), "1.3k"); XCTAssertEqual(ChapterStats.compactCount(1350), "1.4k")
    }
}
