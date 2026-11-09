// SPDX-License-Identifier: AGPL-3.0-or-later
import XCTest
@testable import ChapterCore

final class ChapterLocaleTests: XCTestCase {
    private func catalog() throws -> LocalizedBuiltins {
        // The catalog ships in ChapterCore's own resources (not the test bundle).
        try XCTUnwrap(ChapterLocales.bundled)
    }
    func testOriginalWebLanguagesAndLocalizedSeedsLoad() throws {
        let c = try catalog()
        XCTAssertEqual(c.locales.map(\.id), ["en", "de", "fr", "es", "it", "nl", "fi", "zh", "ja", "ko", "hi", "ar"])
        XCTAssertEqual(c.locales.filter(\.isRightToLeft).map(\.id), ["ar"])
        XCTAssertEqual(c.locales[1].name, "Deutsch")
        XCTAssertEqual(ChapterLocales.seeds(for: "de", in: c).first?.name, "Tagesrückblick")
        XCTAssertEqual(ChapterLocales.seeds(for: "de", in: c).first?.bodyText, "Wie sich der Tag anfühlte\nErinnernswert\nMorgen, eine Sache")
        XCTAssertEqual(ChapterLocales.seeds(for: "en", in: c), BuiltinTemplates.bundled)
        for locale in c.locales {
            for seed in ChapterLocales.seeds(for: locale.id, in: c) {
                XCTAssertNoThrow(try RichDocument(json: seed.bodyJson), locale.id + " " + seed.slug)
                XCTAssertEqual(try RichDocument(json: seed.bodyJson).plainText, seed.bodyText, "Preview equals the web's docToText: " + locale.id + " " + seed.slug)
            }
        }
    }
    func testUnknownOrMissingChoiceIsEnglishLikeOriginalInitI18n() throws {
        let c = try catalog()
        XCTAssertEqual(ChapterLocales.resolve(stored: nil, in: c).id, "en")
        XCTAssertEqual(ChapterLocales.resolve(stored: "xx", in: c).id, "en")
        XCTAssertEqual(ChapterLocales.resolve(stored: "DE", in: c).id, "en", "Ids are exact, like the web's LOCALES lookup")
        XCTAssertEqual(ChapterLocales.resolve(stored: "ar", in: c).id, "ar")
        XCTAssertEqual(ChapterLocales.seeds(for: "xx", in: c).first?.name, "Daily reflection")
    }
    func testMalformedCatalogsRefuse() throws {
        let good = try JSONEncoder().encode(try catalog())
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: good) as? [String: Any])
        var seeds = try XCTUnwrap(object["seeds"] as? [String: Any]); seeds.removeValue(forKey: "fi"); object["seeds"] = seeds
        XCTAssertThrowsError(try ChapterLocales.load(from: JSONSerialization.data(withJSONObject: object)), "Every language needs its seeds")
        var reordered = try XCTUnwrap(JSONSerialization.jsonObject(with: good) as? [String: Any])
        var s2 = try XCTUnwrap(reordered["seeds"] as? [String: [Any]]); s2["de"] = s2["de"]!.reversed(); reordered["seeds"] = s2
        XCTAssertThrowsError(try ChapterLocales.load(from: JSONSerialization.data(withJSONObject: reordered)), "Same slugs in the same order as English")
    }
}
