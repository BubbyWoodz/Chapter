// SPDX-License-Identifier: AGPL-3.0-or-later
import XCTest
@testable import ChapterCore

/// Records every call like the vector script's mock ImportApi.
final class RecordingImportTarget: DayOneImportTarget {
    var importJournals: [(id: String, name: String)]
    var calls: [JSValue] = []
    var entries = 0, medias = 0
    init(_ journals: [(id: String, name: String)]) { importJournals = journals }
    static func n(_ v: Double?) -> JSValue { v.map { .number($0) } ?? .null }
    func importNewJournal(id: String, name: String, subtitle: String, color: String, cover: String) throws {
        calls.append(.array([.string("newJournal"), .string(id), .string(name), .string(subtitle), .string(color), .string(cover)]))
    }
    func importCreateEntry(journalID: String, title: String?, labels: [String]) throws -> String {
        entries += 1
        calls.append(.array([.string("createEntry"), .string(journalID), title.map { .string($0) } ?? .null, .array(labels.map { .string($0) })]))
        return "e\(entries)"
    }
    func importAddMedia(entryID: String, _ m: DayOneArchive.Resolved) async throws -> JSValue? {
        let w = m.width ?? .null, h = m.height ?? .null, d = Self.n(m.durationMs)
        calls.append(.array([.string("addMedia"), .string(entryID), .string(m.kind.rawValue), .string(m.mime), .string(m.data.base64EncodedString()), .string(m.name), w, h, d]))
        if m.kind == .file { return nil }
        medias += 1
        var o: [(String, JSValue)] = [("id", .string("m\(medias)")), ("kind", .string(m.kind.rawValue)), ("mime", .string(m.mime)), ("bytes", .number(Double(m.data.count))), ("name", .string(m.name))]
        if let w = m.width { o.append(("width", w)) }
        if let h = m.height { o.append(("height", h)) }
        if let d = m.durationMs { o.append(("durationMs", .number(d))) }
        o.append(("createdAt", .number(0)))
        return .object(o)
    }
    func importUpdateEntry(id: String, title: String?, bodyJSON: String, bodyText: String, labels: [String], createdAt: Double) throws {
        calls.append(.array([.string("updateEntry"), .string(id), title.map { .string($0) } ?? .null, try JSValue.parse(bodyJSON), .string(bodyText), .array(labels.map { .string($0) }), .number(createdAt)]))
    }
}

final class ChapterDayOneImportTests: XCTestCase {
    /// JSValue equality with objects compared as key sets (the web and native write keys in different orders).
    static func same(_ a: JSValue, _ b: JSValue) -> Bool {
        switch (a, b) {
        case (.object(let x), .object(let y)):
            return x.count == y.count && x.allSatisfy { k in y.contains { $0.0 == k.0 && same(k.1, $0.1) } }
        case (.array(let x), .array(let y)): return x.count == y.count && zip(x, y).allSatisfy { same($0, $1) }
        default: return a == b
        }
    }

    func testDayOneImportMakesTheSameCallsAsTheWebImporter() async throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "dayone-import", withExtension: "json"))
        let f = try JSValue.parse(String(decoding: Data(contentsOf: url), as: UTF8.self))
        guard case .number(let now)? = f.get("now"), case .number(let random)? = f.get("random"), let tz = TimeZone(identifier: f.get("timeZone")?.string ?? ""),
              case .array(let cases)? = f.get("cases") else { return XCTFail("fixture") }
        XCTAssertEqual(cases.count, 4)
        for c in cases {
            let label = c.get("label")?.string ?? ""
            guard case .array(let js)? = c.get("journals"), let web = c.get("result") else { return XCTFail(label) }
            let target = RecordingImportTarget(js.map { ($0.get("id")?.string ?? "", $0.get("name")?.string ?? "") })
            let archive = try DayOneArchive(try XCTUnwrap(Data(base64Encoded: c.get("zip")?.string ?? "")))
            var progress: [JSValue] = []
            var result: [(String, JSValue)]
            do {
                let s = try await ChapterDayOneImport.run(archive, into: target, timeZone: tz, now: { now }, random: { random }) {
                    progress.append(.object([("done", .number(Double($0.done))), ("total", .number(Double($0.total))), ("current", .string($0.current))]))
                }
                result = [("calls", .array(target.calls)), ("progress", .array(progress)), ("summary", .object([
                    ("journals", .number(Double(s.journals))), ("entries", .number(Double(s.entries))), ("media", .number(Double(s.media))), ("skippedMedia", .number(Double(s.skippedMedia)))]))]
            } catch {
                XCTAssertEqual(error as? DayOneArchive.ImportError, .malformed, label)
                result = [("calls", .array(target.calls)), ("progress", .array(progress)), ("error", .string("malformed"))]
            }
            let native = JSValue.object(result)
            XCTAssertTrue(Self.same(native, web), label)
            if !Self.same(native, web), case .array(let nc)? = native.get("calls"), case .array(let wc)? = web.get("calls") {
                for (k, (a, b)) in zip(nc, wc).enumerated() where !Self.same(a, b) { print(label, k, "\nnative:", a.stringify(), "\nweb:   ", b.stringify()); break }
                if nc.count != wc.count { print(label, "call counts", nc.count, wc.count) }
                print("progress/summary native:", (native.get("summary") ?? native.get("error"))!.stringify(), "web:", (web.get("summary") ?? web.get("error"))!.stringify())
            }
        }
    }

    func testJavaScriptLowercaseAndIdStamp() {
        XCTAssertEqual(ChapterDayOneImport.jsLowercase("ΟΔΟΣ"), "οδος")
        XCTAssertEqual(ChapterDayOneImport.jsLowercase("ΣΑ Σ"), "σα σ")
        XCTAssertEqual(ChapterDayOneImport.jsLowercase("İ"), "i\u{307}")
        XCTAssertEqual(ChapterDayOneImport.base36(1767225600000), "mjuohs00")
        XCTAssertEqual(ChapterDayOneImport.base36(123456), "2n9c")
    }
}
