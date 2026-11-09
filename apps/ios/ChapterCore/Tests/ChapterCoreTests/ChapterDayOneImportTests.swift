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
    func importNewJournal(id: String, name: String, subtitle: String, color: String, cover: String) async throws {
        calls.append(.array([.string("newJournal"), .string(id), .string(name), .string(subtitle), .string(color), .string(cover)]))
    }
    func importCreateEntry(journalID: String, title: String?, labels: [String]) async throws -> String {
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
    func importUpdateEntry(id: String, title: String?, bodyJSON: String, bodyText: String, labels: [String], createdAt: Double) async throws {
        calls.append(.array([.string("updateEntry"), .string(id), title.map { .string($0) } ?? .null, try JSValue.parse(bodyJSON), .string(bodyText), .array(labels.map { .string($0) }), .number(createdAt)]))
    }
}

final class ProgressLog: @unchecked Sendable { var items: [JSValue] = [] }

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
            let log = ProgressLog()
            var result: [(String, JSValue)]
            do {
                let s = try await ChapterDayOneImport.run(archive, into: target, timeZone: tz, now: { now }, random: { random }) {
                    log.items.append(.object([("done", .number(Double($0.done))), ("total", .number(Double($0.total))), ("current", .string($0.current))]))
                }
                result = [("calls", .array(target.calls)), ("progress", .array(log.items)), ("summary", .object([
                    ("journals", .number(Double(s.journals))), ("entries", .number(Double(s.entries))), ("media", .number(Double(s.media))), ("skippedMedia", .number(Double(s.skippedMedia)))]))]
            } catch {
                XCTAssertEqual(error as? DayOneArchive.ImportError, .malformed, label)
                result = [("calls", .array(target.calls)), ("progress", .array(log.items)), ("error", .string("malformed"))]
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

    func testImportedEntryCommitsWithItsMediaInOneWriteAndRefusesStrayUploads() throws {
        var snap = VaultSnapshot()
        snap.records.append(VaultRecord(id: "jrec", clock: 1, body: ["kind": .string("journal"), "journalId": .string("j-import-0-x"), "name": .string("Travel")], dirty: true))
        let upload = MediaUpload(id: "0123456789abcdef0123456789abcdef", chunks: 1, cipherBytes: 51, plainBytes: 10, name: "photos-a1.jpeg", mime: "image/jpeg")
        let attrs = JSValue.object([("id", .string(upload.id)), ("kind", .string("image")), ("mime", .string("image/jpeg")), ("bytes", .number(10)), ("name", .string(upload.name)), ("createdAt", .number(5))])
        let doc = JSValue.object([("type", .string("doc")), ("content", .array([.object([("type", .string("mediaAttachment")), ("attrs", attrs)])]))]).stringify()
        let utc = TimeZone(identifier: "UTC")!
        let record = try VaultSnapshot.importedEntry(id: "e1", clock: 1_714_557_600_000, journalID: "j-import-0-x", title: nil, bodyJSON: doc,
                                                     bodyText: "🖼 image photos-a1.jpeg", labels: ["trip"], createdAt: 1_700_000_000_000, timeZone: utc)
        XCTAssertEqual(record.body["title"]?.string, "2024-05-01 10:00:00")
        XCTAssertEqual(record.body["labels"], .array([.string("trip")]))
        XCTAssertEqual(record.body["createdAt"], .number(1_700_000_000_000))
        XCTAssertEqual(record.body["updatedAt"], .number(1_714_557_600_000))
        XCTAssertNil(record.body["chapterNativePlain"])
        XCTAssertEqual(record.mediaReferences.map(\.id), [upload.id])

        var stray = snap
        let plain = try VaultSnapshot.importedEntry(id: "e2", clock: 2, journalID: "j-import-0-x", title: "T", bodyJSON: #"{"type":"doc","content":[{"type":"paragraph"}]}"#, bodyText: "", labels: [], createdAt: 0)
        XCTAssertThrowsError(try stray.addImportedEntry(plain, uploads: [upload])) // not referenced
        XCTAssertEqual(stray, snap)
        var orphan = snap
        let elsewhere = try VaultSnapshot.importedEntry(id: "e3", clock: 2, journalID: "missing", title: "T", bodyJSON: doc, bodyText: "", labels: [], createdAt: 0)
        XCTAssertThrowsError(try orphan.addImportedEntry(elsewhere, uploads: [upload])) // no such notebook
        XCTAssertThrowsError(try VaultSnapshot.importedEntry(id: "e4", clock: 2, journalID: "j", title: nil, bodyJSON: "{", bodyText: "", labels: [], createdAt: 0))

        try snap.addImportedEntry(record, uploads: [upload])
        XCTAssertEqual(snap.records.last?.id, "e1")
        XCTAssertEqual(snap.mediaUploads, [upload])
        XCTAssertThrowsError(try snap.addImportedEntry(record, uploads: [])) // same id twice
        let again = try VaultSnapshot.importedEntry(id: "e5", clock: 3, journalID: "j-import-0-x", title: "T", bodyJSON: doc, bodyText: "", labels: [], createdAt: 0)
        XCTAssertThrowsError(try snap.addImportedEntry(again, uploads: [upload])) // upload already queued
    }
}
