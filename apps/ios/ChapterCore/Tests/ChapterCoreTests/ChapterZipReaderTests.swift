// SPDX-License-Identifier: AGPL-3.0-or-later
import XCTest
@testable import ChapterCore

final class ChapterZipReaderTests: XCTestCase {
    func testReadsFflateArchivesLikeUnzipSync() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "zip-reader", withExtension: "json"))
        let f = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
        for a in f["archives"].array {
            let level = a["level"].number ?? -1
            let reader = try ChapterZipReader(try XCTUnwrap(Data(base64Encoded: a["zip"].string!)))
            let files = a["files"].array
            XCTAssertEqual(reader.jsOrderedNames, files.map { $0["name"].string! }, "level \(level)")
            for file in files {
                let member = try XCTUnwrap(reader.last(named: file["name"].string!))
                XCTAssertEqual(try reader.contents(member).base64EncodedString(), file["base64"].string, "\(file["name"].string!) level \(level)")
            }
        }
        // The Swift writer's archive reads back too, and corrupt or oversized input is refused.
        let zipURL = FileManager.default.temporaryDirectory.appendingPathComponent("chapter-zip-\(UUID().uuidString).zip")
        let w = try ChapterZipWriter(url: zipURL, fallbackMtime: 0); try w.add(path: "a/ü.txt", data: Data("hello".utf8), mtime: 1.7e12); try w.finish()
        let own = try ChapterZipReader(Data(contentsOf: zipURL)); try? FileManager.default.removeItem(at: zipURL)
        XCTAssertEqual(own.members.map(\.name), ["a/ü.txt"]); XCTAssertEqual(try own.contents(own.members[0]), Data("hello".utf8))
        XCTAssertThrowsError(try own.contents(own.members[0], limit: 4))
        XCTAssertThrowsError(try ChapterZipReader(Data("not a zip".utf8)))
        XCTAssertThrowsError(try Inflate.inflate(Data([0xFF, 0xFF, 0xFF]), expected: 1, limit: 10))
    }
}
