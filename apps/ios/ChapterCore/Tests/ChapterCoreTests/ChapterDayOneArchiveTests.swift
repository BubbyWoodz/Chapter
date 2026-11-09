// SPDX-License-Identifier: AGPL-3.0-or-later
import XCTest
@testable import ChapterCore

final class ChapterDayOneArchiveTests: XCTestCase {
    /// Native result in the same shape (and key order) the vector script records from the web importer.
    func run(_ zip: Data) -> JSValue {
        let a: DayOneArchive
        do { a = try DayOneArchive(zip) } catch let e as DayOneArchive.ImportError {
            return .object([("error", .string(e == .notZip ? "notZip" : e == .noJournal ? "noJournal" : "malformed"))])
        } catch { return .object([("error", .string("other"))]) }
        var entries: [JSValue] = []
        for j in a.journals {
            for e in j.entries {
                var resolved: [JSValue] = []
                for (key, kind) in DayOneArchive.kinds {
                    guard case .array(let arr)? = e.get(key) else { continue }
                    for m in arr {
                        do {
                            guard let r = try a.resolve(m, kind) else { resolved.append(.null); continue }
                            var o: [(String, JSValue)] = []
                            if let id = r.identifier { o.append(("identifier", id)) }
                            o += [("kind", .string(r.kind.rawValue)), ("base64", .string(r.data.base64EncodedString())), ("mime", .string(r.mime)), ("name", .string(r.name))]
                            if let w = r.width { o.append(("width", w)) }
                            if let h = r.height { o.append(("height", h)) }
                            if let d = r.durationMs { o.append(("durationMs", d.isFinite ? .number(d) : .null)) }
                            resolved.append(.object(o))
                        } catch { XCTAssertEqual(error as? DayOneArchive.ImportError, .malformed); resolved.append(.string("throws")) }
                    }
                }
                let moments: JSValue
                do {
                    let map = try DayOneArchive.entryMoments(e)
                    moments = .array(map.sorted { $0.key.lexicographicallyPrecedes($1.key) }.map {
                        .array([.string(String(decoding: $0.key, as: UTF16.self)), .string($0.value.kind.rawValue), .string($0.value.moment.stringify())])
                    })
                } catch { moments = .string("throws") }
                entries.append(.object([("resolved", .array(resolved)), ("moments", moments)]))
            }
        }
        return .object([
            ("journals", .array(a.journals.map { .object([("name", .string($0.name)), ("entries", .number(Double($0.entries.count)))]) })),
            ("entryCount", .number(Double(a.entryCount))), ("mediaCount", .number(Double(a.mediaCount))), ("entries", .array(entries)),
        ])
    }

    func testDayOneArchiveParsingResolvingAndMomentsMatchTheWebImporter() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "dayone-archive", withExtension: "json"))
        guard case .array(let cases)? = try JSValue.parse(String(decoding: Data(contentsOf: url), as: UTF8.self)).get("cases") else { return XCTFail("fixture") }
        XCTAssertEqual(cases.count, 9)
        for c in cases {
            let label = try XCTUnwrap(c.get("label")?.string)
            let zip = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(c.get("zip")?.string)))
            let native = run(zip), web = try XCTUnwrap(c.get("result"))
            XCTAssertEqual(native, web, label)
            if native != web { print(label, "\nnative:", native.stringify(), "\nweb:   ", web.stringify()) }
        }
    }

    func testDayOneErrorsUseTheWebImporterMessages() {
        XCTAssertEqual(DayOneArchive.ImportError.notZip.errorDescription, "This file is not a valid .zip — export your Day One journal as JSON and pick the .zip it produces.")
        XCTAssertEqual(DayOneArchive.ImportError.noJournal.errorDescription, "No Day One journal JSON found in the zip. Make sure you exported as JSON, not PDF or plain text.")
        XCTAssertEqual(DayOneArchive.jsRound(-0.4).sign, .minus)
        XCTAssertEqual(DayOneArchive.jsRound(-2.5), -2)
        XCTAssertEqual(DayOneArchive.jsRound(2.5), 3)
        XCTAssertEqual(DayOneArchive.jsRound(0.49999999999999994), 0)
    }
}
