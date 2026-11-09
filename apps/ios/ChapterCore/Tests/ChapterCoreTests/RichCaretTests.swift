// SPDX-License-Identifier: AGPL-3.0-or-later
import XCTest
@testable import ChapterCore

final class RichCaretTests: XCTestCase {
    /// ProseMirror's toJSON adds schema-default attrs (all null here); the web
    /// vectors step re-checks native output through the real schema strictly.
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
    func testInsertionsEqualActualProseMirrorInsertContentAt() throws {
        let cases = try JSONDecoder().decode([JSONValue].self, from: Data(contentsOf: try XCTUnwrap(Bundle.module.url(forResource: "rich-caret", withExtension: "json"))))
        XCTAssertEqual(cases.count, 21)
        var outputs: [JSONValue] = []
        for c in cases {
            var document = try RichDocument(json: json(c["doc"]))
            let caret = RichCaret(block: c["block"].array.map { Int($0.number ?? -1) }, offset: Int(c["offset"].number ?? -1))
            let insert = c["insert"].array
            if insert.first?["type"].string == "entryLink" { try document.insertInline(insert, at: caret) } else { try document.insertBlocks(insert, at: caret) }
            XCTAssertEqual(canonical(document.root), canonical(c["expected"]), c["name"].string ?? "")
            outputs.append(document.root)
        }
        if let output = ProcessInfo.processInfo.environment["CHAPTER_NATIVE_OUTPUT"] { try JSONEncoder().encode(outputs).write(to: URL(fileURLWithPath: output + ".rich-caret")) }
    }
    func testCaretFromEditorLeafCountsInlineNodesAndUTF16() throws {
        let doc = try RichDocument(json: #"{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":"a👩🏽‍💻"},{"type":"entryLink","attrs":{"entryId":"x","label":"X"}},{"type":"hardBreak"},{"type":"text","text":"tail","marks":[{"type":"bold"}]}]},{"type":"paragraph"},{"type":"codeBlock","content":[{"type":"text","text":"code"}]},{"type":"bulletList","content":[{"type":"listItem","content":[{"type":"paragraph","content":[{"type":"text","text":"item"}]}]}]}]}"#)
        XCTAssertEqual(try doc.caret(leaf: [0, 0], utf16Offset: 8), RichCaret(block: [0], offset: 8))
        XCTAssertEqual(try doc.caret(leaf: [0, 3], utf16Offset: 2), RichCaret(block: [0], offset: 12), "8 text units + link + hard break + 2")
        XCTAssertEqual(try doc.caret(leaf: [1], utf16Offset: 0), RichCaret(block: [1], offset: 0))
        XCTAssertEqual(try doc.caret(leaf: [3, 0, 0, 0], utf16Offset: 4), RichCaret(block: [3, 0, 0], offset: 4))
        XCTAssertThrowsError(try doc.caret(leaf: [0, 0], utf16Offset: 9)); XCTAssertThrowsError(try doc.caret(leaf: [0, 1], utf16Offset: 0), "An entry link is not an editor leaf")
        XCTAssertThrowsError(try doc.caret(leaf: [1], utf16Offset: 1)); XCTAssertThrowsError(try doc.caret(leaf: [9], utf16Offset: 0))
        var copy = doc
        XCTAssertThrowsError(try copy.insertInline([.object(["type": .string("entryLink")])], at: RichCaret(block: [0], offset: 2)), "Never split a surrogate pair")
        XCTAssertThrowsError(try copy.insertInline([.object(["type": .string("entryLink")])], at: RichCaret(block: [2], offset: 1)), "Code blocks hold plain text only")
        XCTAssertThrowsError(try copy.insertInline([.object(["type": .string("entryLink")])], at: RichCaret(block: [0], offset: 15)))
        XCTAssertThrowsError(try copy.insertInline([.object(["type": .string("paragraph")])], at: RichCaret(block: [0], offset: 1)))
        XCTAssertThrowsError(try copy.insertInline([.object(["type": .string("text"), "text": .string("x")])], at: RichCaret(block: [0], offset: 1)), "Text-first content is TipTap insertText, not claimed")
        XCTAssertThrowsError(try copy.insertBlocks([.object(["type": .string("paragraph")])], at: RichCaret(block: [3, 0, 0], offset: 1)), "Nested template insertion is not claimed")
        XCTAssertThrowsError(try copy.insertBlocks([], at: RichCaret(block: [1], offset: 0)))
        XCTAssertEqual(try json(copy.root), try json(doc.root), "Refusals never mutate")
    }
    func testRecordInsertionsAreCompareAndSetAndRefuseInvalidTargets() throws {
        let raw = #"{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":"Hello world"}]}],"future":{"keep":1}}"#
        let entry = VaultRecord(id: "e", clock: 5, body: ["title": .string("E"), "bodyJson": .string(raw), "bodyText": .string("Hello world"), "unknown": .bool(true)])
        let target = VaultRecord(id: "t", clock: 1, body: ["title": .string("Target")])
        let linked = try entry.insertingEntryLink(to: target, at: RichCaret(block: [0], offset: 5), expected: raw, now: Date(timeIntervalSince1970: 100))
        XCTAssertEqual(linked.body["bodyText"]?.string, "Hello🔗 Target  world"); XCTAssertEqual(linked.body["unknown"], .bool(true)); XCTAssertTrue(linked.dirty)
        XCTAssertEqual(try RichDocument(json: linked.body["bodyJson"]!.string!).root["future"], .object(["keep": .number(1)]))
        XCTAssertThrowsError(try entry.insertingEntryLink(to: entry, at: RichCaret(block: [0], offset: 0), expected: raw))
        XCTAssertThrowsError(try entry.insertingEntryLink(to: target, at: RichCaret(block: [0], offset: 0), expected: raw + " "), "Stale document refuses")
        var gone = target; gone.deleted = true
        XCTAssertThrowsError(try entry.insertingEntryLink(to: gone, at: RichCaret(block: [0], offset: 0), expected: raw))
        let template = VaultRecord(id: "tpl", clock: 1, body: ["kind": .string("template"), "bodyJson": .string(#"{"type":"doc","content":[{"type":"heading","attrs":{"level":2},"content":[{"type":"text","text":"Prompt"}]}]}"#)])
        let templated = try entry.insertingTemplate(template, at: RichCaret(block: [0], offset: 5), expected: raw)
        XCTAssertEqual(templated.body["bodyText"]?.string, "Hello\nPrompt\n world")
        XCTAssertThrowsError(try entry.insertingTemplate(VaultRecord(id: "t2", clock: 1, body: ["kind": .string("template"), "bodyText": .string("only text")]), at: RichCaret(block: [0], offset: 0), expected: raw), "Web inserts nothing for a template without a rich body")
    }
}
