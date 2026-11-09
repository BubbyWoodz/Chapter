// SPDX-License-Identifier: AGPL-3.0-or-later
import XCTest
@testable import ChapterCore

final class ChapterSearchTests: XCTestCase {
    func testSearchMatchesTheWebSearchSheetInEveryLanguage() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "search", withExtension: "json"))
        let f = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
        let tz = try XCTUnwrap(TimeZone(identifier: f["timeZone"].string!))
        let entries = f["entries"].array.map { e in
            ChapterSearch.Entry(id: e["id"].string!, title: e["title"].string!, labels: e["labels"].array.map { $0.string! }, bodyText: e["bodyText"].string!,
                                createdAt: e["createdAt"].number!, updatedAt: e["updatedAt"].number!, deleted: e["deleted"] == .bool(true))
        }
        XCTAssertEqual(ChapterSearch.monthNames.count, 12)
        var checked = 0
        guard case .object(let locales) = f["vectors"] else { return XCTFail("vectors") }
        for (locale, cases) in locales {
            for c in cases.array {
                let q = c["q"].string!
                XCTAssertEqual(ChapterSearch.toEnglishMonths(ChapterSearch.normalize(q), months: ChapterSearch.monthNames[locale]), c["english"].string, "\(locale) \(q)")
                let got = ChapterSearch.searchHits(entries, query: q, locale: locale, timeZone: tz)
                let want = c["hits"].array.map { ChapterSearch.Hit(id: $0["id"].string!, field: ChapterSearch.Field(rawValue: $0["field"].string!)!, snippet: $0["snippet"].string) }
                XCTAssertEqual(got, want, "\(locale) \(q)")
                checked += 1
            }
        }
        XCTAssertGreaterThan(checked, 400)
        XCTAssertEqual(ChapterSearch.jsLower("ΟΔΟΣ ΣΟΦΟΣ."), "οδος σοφος.")
    }
}
