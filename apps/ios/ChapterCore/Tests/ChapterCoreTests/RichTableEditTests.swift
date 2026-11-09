// SPDX-License-Identifier: AGPL-3.0-or-later
import XCTest
@testable import ChapterCore

final class RichTableEditTests: XCTestCase {
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
    func testTableCommandsEqualActualProsemirrorTables() throws {
        let cases = try JSONDecoder().decode([JSONValue].self, from: Data(contentsOf: try XCTUnwrap(Bundle.module.url(forResource: "rich-table-edit", withExtension: "json"))))
        XCTAssertEqual(cases.count, 24)
        var outputs: [JSONValue] = [], refused = 0
        for c in cases {
            let name = c["name"].string ?? ""
            var document = try RichDocument(json: json(c["doc"]))
            let command = try XCTUnwrap(RichTableCommand(rawValue: c["command"].string ?? ""), name)
            let table = c["table"].array.map { Int($0.number ?? -1) }, row = Int(c["row"].number ?? -1), column = Int(c["col"].number ?? -1)
            if canonical(c["doc"]) == canonical(c["expected"]) {
                XCTAssertThrowsError(try document.applyTableCommand(command, table: table, row: row, column: column), name); refused += 1
            } else {
                try document.applyTableCommand(command, table: table, row: row, column: column)
                XCTAssertEqual(canonical(document.root), canonical(c["expected"]), name)
            }
            outputs.append(document.root)
        }
        XCTAssertEqual(refused, 2)
        if let output = ProcessInfo.processInfo.environment["CHAPTER_NATIVE_OUTPUT"] { try JSONEncoder().encode(outputs).write(to: URL(fileURLWithPath: output + ".rich-table-edit")) }
    }
    func testMergedRaggedAndOutOfRangeTablesRefuseWithoutMutation() throws {
        let doc = try RichDocument(json: #"{"type":"doc","content":[{"type":"table","future":1,"content":[{"type":"tableRow","content":[{"type":"tableCell","attrs":{"colspan":2,"rowspan":1},"content":[{"type":"paragraph"}]}]},{"type":"tableRow","content":[{"type":"tableCell","content":[{"type":"paragraph"}]},{"type":"tableCell","content":[{"type":"paragraph"}]}]}]},{"type":"table","content":[{"type":"tableRow","content":[{"type":"tableCell","content":[{"type":"paragraph"}]}]},{"type":"tableRow","content":[{"type":"tableCell","content":[{"type":"paragraph"}]},{"type":"tableCell","content":[{"type":"paragraph"}]}]}]},{"type":"paragraph"}]}"#)
        var copy = doc
        for command in RichTableCommand.allCases where command != .deleteTable {
            XCTAssertThrowsError(try copy.applyTableCommand(command, table: [0], row: 0, column: 0), "Merged cells: " + command.rawValue)
            XCTAssertThrowsError(try copy.applyTableCommand(command, table: [1], row: 0, column: 0), "Ragged rows: " + command.rawValue)
        }
        XCTAssertThrowsError(try copy.applyTableCommand(.addRowAfter, table: [2], row: 0, column: 0), "Not a table")
        XCTAssertThrowsError(try copy.applyTableCommand(.deleteTable, table: [0], row: 5, column: 0))
        XCTAssertEqual(try json(copy.root), try json(doc.root))
        XCTAssertNil(doc.editableTableRows(at: [0])); XCTAssertNil(doc.editableTableRows(at: [9]))
    }
    func testRowsKeepTheirOwnFieldsAndCellsTheirContent() throws {
        let doc = try RichDocument(json: #"{"type":"doc","content":[{"type":"table","attrs":{"future":"keep"},"content":[{"type":"tableRow","future":{"row":0},"content":[{"type":"tableHeader","attrs":{"colspan":1,"rowspan":1,"colwidth":null,"future":2},"content":[{"type":"paragraph","content":[{"type":"text","text":"H","marks":[{"type":"bold"}]}]}]}]},{"type":"tableRow","future":{"row":1},"content":[{"type":"tableCell","content":[{"type":"paragraph","content":[{"type":"text","text":"x"}]}]}]}]},{"type":"paragraph"}]}"#)
        var copy = doc
        try copy.applyTableCommand(.addRowAfter, table: [0], row: 0, column: 0)
        let rows = copy.root["content"].array[0]["content"].array
        XCTAssertEqual(rows.map { $0["future"] }, [.object(["row": .number(0)]), .null, .object(["row": .number(1)])])
        XCTAssertEqual(copy.root["content"].array[0]["attrs"]["future"], .string("keep"))
        XCTAssertEqual(rows[0]["content"].array[0]["attrs"]["future"], .number(2)); XCTAssertEqual(rows[2]["content"].array[0]["content"].array[0]["content"].array[0]["text"], .string("x"))
        var toggled = doc
        try toggled.applyTableCommand(.toggleHeaderRow, table: [0], row: 1, column: 0)
        let corner = toggled.root["content"].array[0]["content"].array[0]["content"].array[0]
        XCTAssertEqual(corner["type"], .string("tableCell")); XCTAssertEqual(corner["attrs"]["future"], .number(2), "setNodeMarkup keeps attrs and content")
    }
    func testColumnWidthVoteMatchesProsemirrorComputeMap() throws {
        func cell(_ w: Double?) -> JSONValue { .object(["type": .string("tableCell"), "attrs": .object(["colspan": .number(1), "rowspan": .number(1), "colwidth": w.map { .array([.number($0)]) } ?? .null])]) }
        let fixed = try RichDocument.fixingColumnWidths([[cell(100)], [cell(200)], [cell(200)], [cell(nil)]])
        XCTAssertEqual(fixed.map { $0[0]["attrs"]["colwidth"].array.first?.number }, [200, 200, 200, 200], "A width seen once is replaced by the next different one, then counted")
        let agreed = [[cell(90)], [cell(90)]]
        XCTAssertEqual(try RichDocument.fixingColumnWidths(agreed), agreed, "Agreeing columns are untouched")
        let none = [[cell(nil)], [cell(nil)]]
        XCTAssertEqual(try RichDocument.fixingColumnWidths(none), none)
    }
}
