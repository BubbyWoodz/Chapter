// SPDX-License-Identifier: AGPL-3.0-or-later
import XCTest
@testable import ChapterCore

final class ChapterStringsTests: XCTestCase {
    private func fixture() throws -> JSONValue {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "ui-strings", withExtension: "json", subdirectory: "Fixtures") ?? Bundle.module.url(forResource: "ui-strings", withExtension: "json"))
        return try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
    }
    private let params = ["n": "7", "count": "3", "name": "Ada"]

    func testBundledCatalogsCoverTheWebsTwelveLocales() {
        let strings = ChapterStrings.bundled
        XCTAssertEqual(strings.locales, ["en", "de", "fr", "es", "it", "nl", "fi", "zh", "ja", "ko", "hi", "ar"])
        XCTAssertEqual(strings.catalogs["en"]?.count, 860)
        XCTAssertEqual(strings.t("editorx.location.pinned", locale: "xx"), strings.t("editorx.location.pinned", locale: "en"))
    }

    func testTranslateAndPluralsEqualTheWebInEveryLocale() throws {
        let strings = ChapterStrings.bundled, vectors = try fixture()["vectors"]
        for locale in strings.locales {
            let v = vectors[locale]
            for c in v["t"].array { XCTAssertEqual(strings.t(c["key"].string!, params, locale: locale), c["out"].string, locale + " " + c["key"].string!) }
            for c in v["bare"].array { XCTAssertEqual(strings.t(c["key"].string!, locale: locale), c["out"].string, locale) }
            for c in v["plural"].array { XCTAssertEqual(ChapterStrings.pluralCategory(c["n"].number!, locale: locale), c["category"].string, "\(locale) \(c["n"].number!)") }
            var checked = 0
            for c in v["tp"].array { XCTAssertEqual(strings.tp(c["base"].string!, count: c["n"].number!, ["name": "Ada"], locale: locale), c["out"].string, "\(locale) \(c["base"].string!) \(c["n"].number!)"); checked += 1 }
            XCTAssertGreaterThan(checked, 100, locale)
        }
    }

    func testNumbersAndDistancesEqualTheWebInEveryLocale() throws {
        let vectors = try fixture()["vectors"]
        for locale in ChapterStrings.bundled.locales {
            for c in vectors[locale]["numbers"].array {
                let digits = c["opts"]["maximumFractionDigits"].number.map { Int($0) }
                XCTAssertEqual(ChapterStrings.formatNumber(c["n"].number!, locale: locale, fractionDigits: digits), c["out"].string, "\(locale) \(c["n"].number!)")
            }
            for c in vectors[locale]["distances"].array { XCTAssertEqual(LocationCardData.formatDistance(c["km"].number!, locale: locale), c["out"].string, "\(locale) \(c["km"].number!)") }
        }
    }

    func testLocationCardCoercionAndHaversineMatchTheWeb() throws {
        for c in try fixture()["haversine"].array {
            let a = c["a"].array, b = c["b"].array
            let km = LocationCardData.haversineKm(GeoPoint(lat: a[0].number!, lng: a[1].number!, label: ""), GeoPoint(lat: b[0].number!, lng: b[1].number!, label: ""))
            XCTAssertEqual(km, c["km"].number!, accuracy: 1e-9)
        }
        func card(_ json: String) -> LocationCardData? { LocationCardData(try! JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))) }
        XCTAssertNil(card(#"{"from":{"label":"Home"},"map":{"id":"m"}}"#), "from needs numeric lat/lng")
        XCTAssertNil(card(#"{"from":{"lat":1,"lng":2},"map":{"id":""}}"#), "map needs an id")
        let full = try XCTUnwrap(card(#"{"from":{"lat":48.8566,"lng":2.3522,"label":7},"to":{"lat":"x","lng":0},"map":{"id":"m","width":800,"height":400},"photo":{"id":"p","mime":"image/png","bytes":9}}"#))
        XCTAssertEqual(full.from.label, ""); XCTAssertNil(full.to); XCTAssertEqual(full.zoom, 13)
        XCTAssertEqual(full.map.mime, "image/jpeg"); XCTAssertEqual(full.map.kind, "image"); XCTAssertEqual(full.aspectRatio, 2)
        XCTAssertEqual(full.photo?.mime, "image/png"); XCTAssertEqual(full.photo?.bytes, 9); XCTAssertNil(full.distanceKm)
        XCTAssertEqual(try XCTUnwrap(card(#"{"from":{"lat":0,"lng":0},"map":{"id":"m","width":0,"height":5},"zoom":4}"#)).aspectRatio, 600.0 / 340.0)
    }
}
