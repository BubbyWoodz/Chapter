// SPDX-License-Identifier: AGPL-3.0-or-later
import XCTest
@testable import ChapterCore

final class RichSelectionTests: XCTestCase {
    private func canonical(_ value: JSONValue) -> JSONValue {
        switch value {
        case .object(let fields):
            var out: [String: JSONValue] = [:]
            for (key, field) in fields where !(field == .null && key != "type") { out[key] = canonical(field) }
            return .object(out)
        case .array(let items): return .array(items.map(canonical))
        default: return value
        }
    }
    private func json(_ value: JSONValue) throws -> String { let e = JSONEncoder(); e.outputFormatting = [.sortedKeys]; return String(decoding: try e.encode(value), as: UTF8.self) }
    private func fixture() throws -> JSONValue { try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: try XCTUnwrap(Bundle.module.url(forResource: "rich-selection", withExtension: "json")))) }

    func testSchemaMarkRankAndExclusionsEqualOriginalWebSchema() throws {
        let f = try fixture()
        XCTAssertEqual(f["markOrder"].array.compactMap(\.string), RichDocument.markOrder)
        guard case .object(let exclusions) = f["markExclusions"] else { return XCTFail("exclusions") }
        XCTAssertEqual(Set(exclusions.keys), Set(RichDocument.markExclusions.keys))
        for (mark, list) in exclusions { XCTAssertEqual(Set(list.array.compactMap(\.string)), RichDocument.markExclusions[mark]) }
        func types(_ marks: [JSONValue]) -> [String?] { marks.map { $0["type"].string } }
        let m: (String) -> JSONValue = { .object(["type": .string($0)]) }
        XCTAssertEqual(types(RichDocument.insertingMark(m("bold"), into: [m("italic")])), ["bold", "italic"])
        XCTAssertEqual(types(RichDocument.insertingMark(m("italic"), into: [m("link"), m("strike")])), ["link", "italic", "strike"])
        XCTAssertEqual(types(RichDocument.insertingMark(m("italic"), into: [m("future"), m("bold")])), ["future", "bold", "italic"], "Unknown marks keep their place")
        XCTAssertEqual(types(RichDocument.insertingMark(m("future"), into: [m("bold")])), ["bold", "future"])
    }
    func testSelectionFormattingEqualsActualTipTapToggleMark() throws {
        let cases = try fixture()["cases"].array
        XCTAssertEqual(cases.count, 23)
        var outputs: [JSONValue] = [], refused = 0
        for c in cases {
            let name = c["name"].string ?? ""
            var document = try RichDocument(json: json(c["doc"]))
            let leaf = c["leaf"].array.map { Int($0.number ?? -1) }, range = Int(c["from"].number ?? -1)..<Int(c["to"].number ?? -1)
            if canonical(c["doc"]) == canonical(c["expected"]) {
                // The web makes no change here: native refuses instead of writing a no-op.
                XCTAssertThrowsError(try document.toggleMark(c["mark"].string ?? "", leaf: leaf, utf16Range: range), name); refused += 1
            } else {
                try document.toggleMark(c["mark"].string ?? "", leaf: leaf, utf16Range: range)
                XCTAssertEqual(canonical(document.root), canonical(c["expected"]), name)
            }
            outputs.append(document.root)
        }
        XCTAssertEqual(refused, 2)
        if let output = ProcessInfo.processInfo.environment["CHAPTER_NATIVE_OUTPUT"] { try JSONEncoder().encode(outputs).write(to: URL(fileURLWithPath: output + ".rich-selection")) }
    }
    func testSelectionRefusalsNeverMutateAndKeepOpaqueFields() throws {
        let doc = try RichDocument(json: #"{"type":"doc","content":[{"type":"paragraph","future":1,"content":[{"type":"text","text":"a👩🏽‍💻b","future":{"keep":true}},{"type":"text","text":"link","marks":[{"type":"link","attrs":{"href":"https://example.invalid"}}]},{"type":"text","text":"odd","marks":[{"type":"futureMark","attrs":{"k":1}}]}]},{"type":"paragraph"}]}"#)
        var copy = doc
        XCTAssertThrowsError(try copy.toggleMark("bold", leaf: [0, 0], utf16Range: 1..<2), "Never split a surrogate pair")
        XCTAssertThrowsError(try copy.toggleMark("bold", leaf: [0, 0], utf16Range: 2..<2), "Empty selection is whole-run formatting, not this")
        XCTAssertThrowsError(try copy.toggleMark("bold", leaf: [0, 0], utf16Range: 0..<10))
        XCTAssertThrowsError(try copy.toggleMark("link", leaf: [0, 0], utf16Range: 0..<1), "Only the native toolbar marks")
        XCTAssertThrowsError(try copy.toggleMark("code", leaf: [0, 1], utf16Range: 0..<2), "Adding code would silently erase a link")
        XCTAssertThrowsError(try copy.toggleMark("bold", leaf: [1], utf16Range: 0..<1), "An empty textblock has no text leaf")
        XCTAssertThrowsError(try copy.toggleMark("bold", leaf: [0, 9], utf16Range: 0..<1))
        XCTAssertEqual(try json(copy.root), try json(doc.root))
        try copy.toggleMark("bold", leaf: [0, 0], utf16Range: 1..<8)
        let parts = copy.root["content"].array[0]["content"].array
        XCTAssertEqual(parts.map { $0["text"].string }, ["a", "👩🏽‍💻", "b", "link", "odd"])
        XCTAssertTrue(parts[0...2].allSatisfy { $0["future"] == .object(["keep": .bool(true)]) }, "Every split piece keeps the leaf's own fields")
        XCTAssertEqual(copy.root["content"].array[0]["future"], .number(1))
        var future = doc
        try future.toggleMark("bold", leaf: [0, 2], utf16Range: 0..<1)
        XCTAssertEqual(future.root["content"].array[0]["content"].array[2]["marks"].array.map { $0["type"].string }, ["futureMark", "bold"], "Unknown marks are preserved in place")
    }
    func testRecordSelectionFormattingIsCompareAndSet() throws {
        let raw = #"{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":"Hello world"}]}]}"#
        let entry = VaultRecord(id: "e", clock: 5, body: ["title": .string("E"), "bodyJson": .string(raw), "bodyText": .string("Hello world"), "unknown": .bool(true)])
        let bold = try entry.togglingMark("bold", leaf: [0, 0], utf16Range: 6..<11, expected: raw, now: Date(timeIntervalSince1970: 100))
        XCTAssertEqual(bold.body["bodyText"]?.string, "Hello world"); XCTAssertEqual(bold.body["unknown"], .bool(true)); XCTAssertTrue(bold.dirty)
        XCTAssertEqual(try RichDocument(json: bold.body["bodyJson"]!.string!).root["content"].array[0]["content"].array.count, 2)
        XCTAssertThrowsError(try entry.togglingMark("bold", leaf: [0, 0], utf16Range: 0..<1, expected: raw + " "), "Stale document refuses")
    }
    func testWholeRunFormattingUsesOriginalRankOrder() throws {
        let raw = #"{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":"x","marks":[{"type":"italic"}]}]}]}"#
        let draft = try RichDraft(entryID: "e", path: [0, 0], expectedDocument: raw, text: "x").togglingMark("bold")
        XCTAssertEqual(draft.marks?.map { $0["type"].string }, ["bold", "italic"])
    }
}
