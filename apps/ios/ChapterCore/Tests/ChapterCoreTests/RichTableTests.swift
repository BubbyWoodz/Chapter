// SPDX-License-Identifier: AGPL-3.0-or-later
import XCTest
@testable import ChapterCore

final class RichTableTests: XCTestCase {
    func cases() throws -> [JSONValue] { try JSONDecoder().decode([JSONValue].self, from: Data(contentsOf: try XCTUnwrap(Bundle.module.url(forResource:"rich-tables",withExtension:"json")))) }
    func layout(_ table: JSONValue) throws -> RichTableLayout? {
        let doc = String(decoding: try JSONEncoder().encode(JSONValue.object(["type": .string("doc"), "content": .array([table])])), as: UTF8.self)
        return RichTableLayout(table: try RichDocument(json: doc).node.children[0])
    }
    func testGridEqualsActualProseMirrorTableMapIncludingProblems() throws {
        let all = try cases(); XCTAssertEqual(all.count, 9)
        for value in all {
            let name = value["name"].string ?? "?"
            let grid = try XCTUnwrap(try layout(value["table"]), name)
            XCTAssertEqual(grid.width, Int(value["width"].number ?? -1), name); XCTAssertEqual(grid.height, Int(value["height"].number ?? -1), name)
            XCTAssertEqual(grid.map, value["map"].array.map { Int($0.number ?? -1) }, name)
            // "colwidth mismatch" comes from findBadColWidths (width repair), which
            // native deliberately does not emulate: it shows natural widths instead.
            XCTAssertEqual(grid.problems, value["problems"].array.compactMap(\.string).filter { $0 != "colwidth mismatch" }, name)
        }
    }
    func testCellRectanglesHeadersAndAgreedWidthsNeverGuess() throws {
        let all = try cases(); func named(_ n: String) throws -> RichTableLayout { try XCTUnwrap(try layout(try XCTUnwrap(all.first { $0["name"].string == n })["table"])) }
        let mixed = try named("mixed")
        XCTAssertEqual(mixed.cells.map { [$0.row, $0.column, $0.rowSpan, $0.columnSpan] }, [[0,0,2,2],[0,2,1,1],[1,2,1,1],[2,0,1,1],[2,1,1,1],[2,2,1,1]])
        XCTAssertEqual(mixed.cells[0].path, [0, 0, 0])
        XCTAssertEqual(try named("simpleHeader").cells.map(\.header), [true, true, false, false])
        XCTAssertEqual(try named("colspan").columnWidths, [120, 80]); XCTAssertEqual(try named("conflictingWidths").columnWidths, [nil, nil])
        XCTAssertEqual(try named("overlong").cells[0].rowSpan, 2, "Overlong rowspan is clipped to the table like the map")
        let collision = try named("collision"); XCTAssertEqual(collision.cells.last.map { [$0.row, $0.column, $0.rowSpan, $0.columnSpan] }, [1, 0, 1, 1])
    }
    func testInvalidSpansAndNonTableChildrenFallBackWithoutMutation() throws {
        let cell: (JSONValue) -> JSONValue = { .object(["type": .string("tableCell"), "attrs": .object(["colspan": $0]), "content": .array([])]) }
        for bad: JSONValue in [.number(0), .number(-1), .number(1.5), .number(1001), .string("2"), .bool(true)] {
            XCTAssertNil(try layout(.object(["type": .string("table"), "content": .array([.object(["type": .string("tableRow"), "content": .array([cell(bad)])])])])))
        }
        XCTAssertNil(try layout(.object(["type": .string("table"), "content": .array([.object(["type": .string("paragraph"), "content": .array([])])])])))
        XCTAssertNil(try layout(.object(["type": .string("table"), "content": .array([.object(["type": .string("tableRow"), "content": .array([.object(["type": .string("futureCell")])])])])])))
        let huge = try XCTUnwrap(try layout(.object(["type": .string("table"), "content": .array([])])))
        XCTAssertEqual(huge.problems, ["zero_sized"])
    }
    func testCustomBlockLabelsMatchOriginalDocPreviewTruthiness() {
        func o(_ d: [String: JSONValue]) -> JSONValue { .object(d) }
        XCTAssertEqual(RichCustomBlockLabel.location(o(["from": o(["label": .string("Home")]), "to": o(["label": .string("Café")])])), "📍 Home → Café")
        XCTAssertEqual(RichCustomBlockLabel.location(o(["from": o(["label": .string("Home")]), "to": o(["label": .string("")])])), "📍 Home")
        XCTAssertEqual(RichCustomBlockLabel.location(o(["from": o(["label": .string("")])])), "📍 Location")
        XCTAssertEqual(RichCustomBlockLabel.location(o(["from": o(["label": .number(3)]), "to": o(["label": .string("Pier")])])), "📍 Location → Pier")
        XCTAssertEqual(RichCustomBlockLabel.location(.null), "📍 Location")
        XCTAssertEqual(RichCustomBlockLabel.videoInterview(o(["typeName": .string("Origin story"), "cards": .array([.null])])), "🎬 Origin story · 1 question")
        XCTAssertEqual(RichCustomBlockLabel.videoInterview(o(["typeName": .string(""), "cards": .array([.null, .null, .null])])), "🎬 Video interview · 3 questions")
        XCTAssertEqual(RichCustomBlockLabel.videoInterview(o(["cards": .object([:])])), "🎬 Video interview")
    }
}
