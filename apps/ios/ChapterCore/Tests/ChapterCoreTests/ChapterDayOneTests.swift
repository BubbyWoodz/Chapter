// SPDX-License-Identifier: AGPL-3.0-or-later
import XCTest
@testable import ChapterCore

final class ChapterDayOneTests: XCTestCase {
    func testMarkdownBlocksTitlesAndMomentURLsMatchTheWebImporter() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "dayone-markdown", withExtension: "json"))
        let f = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
        XCTAssertGreaterThan(f["cases"].array.count, 20)
        for c in f["cases"].array {
            let md = try XCTUnwrap(c["md"].string)
            let blocks = ChapterDayOne.markdownToBlocks(md)
            XCTAssertEqual(JSONValue.array(blocks), c["blocks"], md)
            let split = ChapterDayOne.splitTitle(blocks)
            XCTAssertEqual(split.title, c["split"]["title"].string, md)
            XCTAssertEqual(JSONValue.array(split.body), c["split"]["body"], md)
        }
        for m in f["moments"].array {
            let ref = ChapterDayOne.parseMomentURL(m["url"].string!)
            if m["ref"] == .null { XCTAssertNil(ref, m["url"].string!) }
            else { XCTAssertEqual(ref?.kind.rawValue, m["ref"]["kind"].string, m["url"].string!); XCTAssertEqual(ref?.identifier, m["ref"]["identifier"].string, m["url"].string!) }
        }
    }
}
