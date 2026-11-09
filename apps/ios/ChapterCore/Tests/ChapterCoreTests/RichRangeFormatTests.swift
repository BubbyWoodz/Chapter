// SPDX-License-Identifier: AGPL-3.0-or-later
import XCTest
@testable import ChapterCore

final class RichRangeFormatTests: XCTestCase {
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
    private func cases() throws -> [JSONValue] { try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: try XCTUnwrap(Bundle.module.url(forResource: "rich-range-format", withExtension: "json")))).array }

    func testMultiRunFormattingEqualsActualTipTapToggleMark() throws {
        let all = try cases()
        XCTAssertEqual(all.count, 25)
        var outputs: [JSONValue] = [], refused = 0
        for c in all {
            let name = c["name"].string ?? ""
            var document = try RichDocument(json: json(c["doc"]))
            let block = c["block"].array.map { Int($0.number ?? -1) }, range = Int(c["from"].number ?? -1)..<Int(c["to"].number ?? -1)
            if canonical(c["doc"]) == canonical(c["expected"]) {
                // The web makes no change here: native refuses instead of writing a no-op.
                XCTAssertThrowsError(try document.toggleMark(c["mark"].string ?? "", block: block, range: range), name); refused += 1
            } else {
                try document.toggleMark(c["mark"].string ?? "", block: block, range: range)
                XCTAssertEqual(canonical(document.root), canonical(c["expected"]), name)
            }
            outputs.append(document.root)
        }
        XCTAssertEqual(refused, 2)
        if let output = ProcessInfo.processInfo.environment["CHAPTER_NATIVE_OUTPUT"] { try JSONEncoder().encode(outputs).write(to: URL(fileURLWithPath: output + ".rich-range-format")) }
    }
    func testFormattingTextPositionsEqualProseMirrorPositions() throws {
        let doc = try RichDocument(json: #"{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":"a👍"},{"type":"entryLink","attrs":{"entryId":"e","label":"Linked"}},{"type":"hardBreak"},{"type":"text","text":"b","marks":[{"type":"bold"}]}]},{"type":"bulletList","content":[{"type":"listItem","content":[{"type":"paragraph"}]}]}]}"#)
        let text = try doc.formattingText(block: [0])
        XCTAssertEqual(text, "a👍\u{FFFC}\u{FFFC}b"); XCTAssertEqual(text.utf16.count, 6)
        XCTAssertEqual(try doc.formattingText(block: [1, 0, 0]), "")
        XCTAssertThrowsError(try doc.formattingText(block: [1]), "A list is not a textblock")
    }
    func testFormattableBlocksAreKnownTextblocksWithContent() throws {
        let doc = try RichDocument(json: #"{"type":"doc","content":[{"type":"heading","attrs":{"level":2},"content":[{"type":"text","text":"H"}]},{"type":"paragraph"},{"type":"codeBlock","content":[{"type":"text","text":"x"}]},{"type":"blockquote","content":[{"type":"paragraph","content":[{"type":"text","text":"q"}]}]},{"type":"table","content":[{"type":"tableRow","content":[{"type":"tableCell","content":[{"type":"paragraph","content":[{"type":"text","text":"c"}]}]}]}]},{"type":"futureNode","content":[{"type":"paragraph","content":[{"type":"text","text":"opaque"}]}]}]}"#)
        XCTAssertEqual(doc.formattableBlocks, [[0], [3, 0], [4, 0, 0, 0]], "Opaque future nodes are never entered")
        for path in doc.formattableBlocks { XCTAssertFalse(try doc.formattingText(block: path).isEmpty) }
    }
    func testRangeRefusalsNeverMutateAndKeepOpaqueFields() throws {
        let doc = try RichDocument(json: #"{"type":"doc","content":[{"type":"paragraph","future":1,"content":[{"type":"text","text":"a👩🏽‍💻","future":{"keep":true}},{"type":"text","text":"link","marks":[{"type":"link","attrs":{"href":"https://example.invalid"}}]},{"type":"text","text":"odd","marks":[{"type":"futureMark","attrs":{"k":1}}]},{"type":"futureInline","attrs":{"x":[1]}}]},{"type":"codeBlock","content":[{"type":"text","text":"let"}]},{"type":"paragraph"}]}"#)
        var copy = doc
        XCTAssertThrowsError(try copy.toggleMark("bold", block: [0], range: 1..<2), "Never split a surrogate pair")
        XCTAssertThrowsError(try copy.toggleMark("bold", block: [0], range: 2..<5), "Never start inside a surrogate pair either")
        XCTAssertThrowsError(try copy.toggleMark("bold", block: [0], range: 3..<3), "Empty selection")
        XCTAssertThrowsError(try copy.toggleMark("bold", block: [0], range: 0..<17), "Past the end")
        XCTAssertThrowsError(try copy.toggleMark("link", block: [0], range: 0..<1), "Only the native toolbar marks")
        XCTAssertThrowsError(try copy.toggleMark("code", block: [0], range: 0..<12), "Adding code would silently erase a link")
        XCTAssertThrowsError(try copy.toggleMark("bold", block: [1], range: 0..<2), "Code blocks take no marks")
        XCTAssertThrowsError(try copy.toggleMark("bold", block: [2], range: 0..<1))
        XCTAssertThrowsError(try copy.toggleMark("bold", block: [9], range: 0..<1))
        XCTAssertEqual(try json(copy.root), try json(doc.root))
        try copy.toggleMark("bold", block: [0], range: 1..<16)
        let parts = copy.root["content"].array[0]["content"].array
        XCTAssertEqual(parts.map { $0["text"].string }, ["a", "👩🏽‍💻", "link", "odd", nil])
        XCTAssertEqual(parts[0]["marks"].array.count, 0); XCTAssertEqual(parts[1]["marks"].array.map { $0["type"].string }, ["bold"])
        XCTAssertTrue(parts[0...1].allSatisfy { $0["future"] == .object(["keep": .bool(true)]) }, "Split pieces keep the run's own fields")
        XCTAssertEqual(parts[2]["marks"].array.map { $0["type"].string }, ["link", "bold"], "Link keeps its attributes and rank")
        XCTAssertEqual(parts[2]["marks"].array[0]["attrs"]["href"].string, "https://example.invalid")
        XCTAssertEqual(parts[3]["marks"].array.map { $0["type"].string }, ["futureMark", "bold"], "Unknown marks stay in place")
        XCTAssertEqual(parts[4]["attrs"]["x"], .array([.number(1)])); XCTAssertEqual(parts[4]["marks"].array.map { $0["type"].string }, ["bold"])
        XCTAssertEqual(copy.root["content"].array[0]["future"], .number(1))
        XCTAssertEqual(copy.root["content"].array[1], doc.root["content"].array[1])
    }
    func testSingleRunRangeMatchesLeafFormatting() throws {
        let raw = #"{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":"Hello "},{"type":"text","text":"world","marks":[{"type":"italic"}]}]}]}"#
        for (mark, range) in [("bold", 1..<4), ("italic", 0..<3), ("code", 2..<6)] {
            var byLeaf = try RichDocument(json: raw), byBlock = byLeaf
            try byLeaf.toggleMark(mark, leaf: [0, 0], utf16Range: range); try byBlock.toggleMark(mark, block: [0], range: range)
            XCTAssertEqual(try json(byLeaf.root), try json(byBlock.root), mark)
        }
    }
    func testRecordMultiRunFormattingIsCompareAndSet() throws {
        let raw = #"{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":"ab","marks":[{"type":"bold"}]},{"type":"text","text":"cd"}]}]}"#
        let entry = VaultRecord(id: "e", clock: 5, body: ["title": .string("E"), "bodyJson": .string(raw), "bodyText": .string("abcd"), "unknown": .bool(true)])
        let bold = try entry.togglingMark("bold", block: [0], range: 0..<4, expected: raw, now: Date(timeIntervalSince1970: 100))
        XCTAssertEqual(bold.body["bodyText"]?.string, "abcd"); XCTAssertEqual(bold.body["unknown"], .bool(true)); XCTAssertTrue(bold.dirty)
        XCTAssertEqual(try RichDocument(json: bold.body["bodyJson"]!.string!).root["content"].array[0]["content"].array.count, 1)
        XCTAssertThrowsError(try entry.togglingMark("bold", block: [0], range: 0..<1, expected: raw + " "), "Stale document refuses")
    }
}
