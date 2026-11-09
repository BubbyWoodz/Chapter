// SPDX-License-Identifier: AGPL-3.0-or-later
import XCTest
@testable import ChapterCore

final class ChapterMarkdownTests: XCTestCase {
    func testDocToMarkdownAndJSONMatchTheWeb() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "markdown", withExtension: "json"))
        let cases = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url)).array
        XCTAssertGreaterThan(cases.count, 100)
        // The one documented difference: a lone UTF-16 surrogate (JSON.stringify writes
        // `\ud800`) can't live in a Swift String and is U+FFFD, as in every vault record.
        let lone = try NSRegularExpression(pattern: #"\\ud[89a-f][0-9a-f]{2}"#)
        func native(_ s: String?) -> String? { s.map { lone.stringByReplacingMatches(in: $0, range: NSRange($0.startIndex..., in: $0), withTemplate: "\u{FFFD}") } }
        for c in cases {
            let json = try XCTUnwrap(c["json"].string)
            guard c["parsed"] == .bool(true) else { XCTAssertThrowsError(try JSValue.parse(json), json); continue }
            let v: JSValue
            do { v = try JSValue.parse(json) } catch { XCTFail("JSON.parse accepts: \(json)"); continue }
            XCTAssertEqual(v.stringify(), native(c["stringify"].string), json)
            switch v { case .object, .array: break; default: continue }
            if c["throws"] == .bool(true) { XCTAssertThrowsError(try ChapterMarkdown.docToMarkdown(v), json) }
            else { XCTAssertEqual(try? ChapterMarkdown.docToMarkdown(v), native(c["markdown"].string), json) }
        }
        for (x, s) in [(1e21, "1e+21"), (1e-7, "1e-7"), (123456789012345680000, "123456789012345680000"), (0.1 + 0.2, "0.30000000000000004"), (-1.5e-10, "-1.5e-10"), (5e-324, "5e-324"), (2e-6, "0.000002")] {
            XCTAssertEqual(JSValue.numberString(x), s)
        }
    }
}
