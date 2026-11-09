// SPDX-License-Identifier: AGPL-3.0-or-later
import XCTest
@testable import ChapterCore

final class ChapterExportTests: XCTestCase {
    func testArchiveMatchesTheWebExportJournal() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "journal-export", withExtension: "json"))
        let f = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
        let j = f["journal"]
        let journal = ChapterExport.Journal(id: j["id"].string!, name: j["name"].string!, subtitle: j["subtitle"].string ?? "", color: j["color"].string ?? "", cover: j["cover"].string ?? "", createdAt: j["createdAt"].number, updatedAt: j["updatedAt"].number)
        let entries = f["entries"].array.map { e in
            ChapterExport.Entry(id: e["id"].string!, journalId: e["journalId"].string!, title: e["title"].string!, bodyText: e["bodyText"].string!, bodyJson: e["bodyJson"].string,
                                labels: e["labels"].array.map { $0.string! }, createdAt: e["createdAt"].number!, updatedAt: e["updatedAt"].number!, attachments: e["attachments"].array, deleted: e["deleted"] == .bool(true))
        }
        let available = f["available"]
        let archive = try ChapterExport.archive(journal: journal, entries: entries, now: f["now"].number!, generator: ("Mneme", "test"),
            media: { _, att in available[att["id"].string ?? ""].array.isEmpty ? nil : Data(available[att["id"].string!].array.map { UInt8($0.number!) }) }, markdown: { _ in nil })
        XCTAssertEqual(archive.filename, f["filename"].string)
        guard case .object(let expected) = f["files"] else { return XCTFail("files") }
        XCTAssertEqual(Set(archive.files.map(\.path)), Set(expected.keys))
        for file in archive.files {
            let want = try XCTUnwrap(expected[file.path], file.path)
            if file.path.hasSuffix(".json") {
                var got = try JSONDecoder().decode(JSONValue.self, from: file.data)
                if file.path.hasPrefix("entries/"), case .object(var o) = got { o.removeValue(forKey: "markdown"); got = .object(o) }
                XCTAssertEqual(got, want, file.path)
            } else if file.path.hasSuffix(".md") { XCTAssertEqual(String(decoding: file.data, as: UTF8.self), want.string, file.path) }
            else { XCTAssertEqual(file.data.base64EncodedString(), want.string, file.path) }
        }
        for s in f["slugs"].array { XCTAssertEqual(ChapterExport.slugify(s["name"].string!), s["slug"].string, s["name"].string!) }
        // The real archive, unzipped by the web script (fflate) when CHAPTER_NATIVE_OUTPUT is set.
        let zipURL = FileManager.default.temporaryDirectory.appendingPathComponent("chapter-export-\(UUID().uuidString).zip")
        let writer = try ChapterZipWriter(url: zipURL)
        for file in archive.files { try writer.add(path: file.path, data: file.data, mtime: file.mtime) }
        try writer.finish()
        let zip = try Data(contentsOf: zipURL); try? FileManager.default.removeItem(at: zipURL)
        XCTAssertEqual(zip.suffix(22).prefix(4), Data([0x50, 0x4b, 0x05, 0x06]))
        if let out = ProcessInfo.processInfo.environment["CHAPTER_NATIVE_OUTPUT"] { try zip.write(to: URL(fileURLWithPath: out + ".journal-export.zip")) }
        XCTAssertEqual(ChapterZipWriter.crc32(Data("123456789".utf8)), 0xCBF43926)
        XCTAssertEqual(ChapterExport.iso(0), "1970-01-01T00:00:00.000Z"); XCTAssertEqual(ChapterExport.iso(-1), "1969-12-31T23:59:59.999Z")
        XCTAssertEqual(ChapterExport.iso(253402300800000), "+010000-01-01T00:00:00.000Z"); XCTAssertNil(ChapterExport.iso(.nan))
    }
}
