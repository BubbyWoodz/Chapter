// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

/// The original table toolbar (editor/Toolbar.tsx TABLE_TOOLS), with the cursor
/// in one cell. Verified against the real TipTap/prosemirror-tables commands
/// (rich-table-edit.json). Only rectangular tables without merged cells are
/// edited; merged or malformed tables are refused rather than approximated.
public enum RichTableCommand: String, Codable, CaseIterable {
    case addRowAfter, addColumnAfter, deleteRow, deleteColumn, toggleHeaderRow, deleteTable
    public var title: String {
        switch self {
        case .addRowAfter: return "Add row below"
        case .addColumnAfter: return "Add column right"
        case .deleteRow: return "Delete row"
        case .deleteColumn: return "Delete column"
        case .toggleHeaderRow: return "Toggle header row"
        case .deleteTable: return "Delete table"
        }
    }
}

public extension RichDocument {
    private static let cellTypes: Set<String> = ["tableCell", "tableHeader"]

    /// Cells of an editable table at `path`, row-major; nil when merged, ragged or not a table.
    func editableTableRows(at path: [Int]) -> [[JSONValue]]? {
        var value = root
        for index in path {
            let children = value["content"].array
            guard children.indices.contains(index) else { return nil }
            value = children[index]
        }
        guard value["type"].string == "table" else { return nil }
        let rows = value["content"].array.map { $0["content"].array }
        guard !rows.isEmpty, value["content"].array.allSatisfy({ $0["type"].string == "tableRow" }), let width = rows.first?.count, width > 0,
              rows.allSatisfy({ $0.count == width }) else { return nil }
        for cell in rows.joined() {
            guard Self.cellTypes.contains(cell["type"].string ?? "") else { return nil }
            for key in ["colspan", "rowspan"] {
                let span = cell["attrs"][key]
                guard span == .null || span.number == 1 else { return nil }
            }
        }
        return rows
    }

    /// Paths of every table in document order (including tables nested in blocks).
    var tablePaths: [[Int]] {
        var found: [[Int]] = []
        func walk(_ node: JSONValue, _ path: [Int]) {
            if node["type"].string == "table", !path.isEmpty { found.append(path) }
            for (i, child) in node["content"].array.enumerated() where child["type"].string != "text" { walk(child, path + [i]) }
        }
        walk(root, []); return found
    }
    /// The plain text of a cell, for labelling it in the native table editor.
    static func cellText(_ cell: JSONValue) -> String {
        if let text = cell["text"].string { return text }
        return cell["content"].array.map(cellText).joined(separator: cell["type"].string == "tableCell" || cell["type"].string == "tableHeader" ? " " : "")
    }
    mutating func applyTableCommand(_ command: RichTableCommand, table path: [Int], row: Int, column: Int) throws {
        let parentPath = Array(path.dropLast())
        guard let index = path.last, var rows = editableTableRows(at: path),
              rows.indices.contains(row), rows[row].indices.contains(column) else { throw ChapterError.unsupported }
        let height = rows.count, width = rows[0].count
        func type(_ r: Int, _ c: Int) -> String { rows[r][c]["type"].string ?? "" }
        func rowIsHeader(_ r: Int) -> Bool { (0..<width).allSatisfy { type(r, $0) == "tableHeader" } }
        func columnIsHeader(_ c: Int) -> Bool { (0..<height).allSatisfy { type($0, c) == "tableHeader" } }
        func empty(_ kind: String) -> JSONValue {
            .object(["type": .string(kind), "attrs": .object(["colspan": .number(1), "rowspan": .number(1), "colwidth": .null]), "content": .array([.object(["type": .string("paragraph")])])])
        }
        switch command {
        case .deleteTable:
            try replacingChild(parentPath, at: index) { _ in [] }
            return
        case .addRowAfter:
            // prosemirror-tables addRow: the reference row is the one above,
            // unless it is a header row (then the one below, or a plain cell).
            let at = row + 1
            var reference: Int? = at > 0 ? -1 : 0
            if rowIsHeader(at + reference!) { reference = (at == 0 || at == height) ? nil : 0 }
            rows.insert((0..<width).map { c in empty(reference.map { type(at + $0, c) } ?? "tableCell") }, at: at)
        case .addColumnAfter:
            let at = column + 1
            var reference: Int? = at > 0 ? -1 : 0
            if columnIsHeader(at + reference!) { reference = (at == 0 || at == width) ? nil : 0 }
            for r in 0..<height { rows[r].insert(empty(reference.map { type(r, at + $0) } ?? "tableCell"), at: at) }
        case .deleteRow:
            guard height > 1 else { throw ChapterError.unsupported } // the original does nothing
            rows.remove(at: row)
        case .deleteColumn:
            guard width > 1 else { throw ChapterError.unsupported }
            for r in 0..<height { rows[r].remove(at: column) }
        case .toggleHeaderRow:
            // toggleHeader('row'): skip the corner when the first column is a header column.
            let rowEnabled = rowIsHeader(0), start = columnIsHeader(0) ? 1 : 0
            for c in start..<width {
                guard case .object(var fields) = rows[0][c] else { throw ChapterError.unsupported }
                fields["type"] = .string(rowEnabled ? "tableCell" : "tableHeader"); rows[0][c] = .object(fields)
            }
        }
        rows = try Self.fixingColumnWidths(rows)
        try replacingChild(parentPath, at: index) { table in
            guard case .object(var fields) = table else { throw ChapterError.unsupported }
            let oldRows = table["content"].array
            // Existing rows keep their own fields; new rows are plain tableRow nodes.
            var source = oldRows
            if command == .addRowAfter { source.insert(.object(["type": .string("tableRow")]), at: row + 1) }
            if command == .deleteRow { source.remove(at: row) }
            fields["content"] = .array(zip(source, rows).map { rowNode, cells in
                guard case .object(var rowFields) = rowNode else { return rowNode }
                rowFields["content"] = .array(cells); return .object(rowFields)
            })
            return [.object(fields)]
        }
    }

    /// prosemirror-tables computeMap + findBadColWidths, as fixTables applies them
    /// after every table transaction: a column's voted width is copied onto cells
    /// that lack or disagree with it, whenever not every cell in that column has it.
    internal static func fixingColumnWidths(_ rows: [[JSONValue]]) throws -> [[JSONValue]] {
        let height = rows.count, width = rows.first?.count ?? 0
        var widths = [Double?](repeating: nil, count: width), counts = [Int](repeating: 0, count: width)
        func first(_ cell: JSONValue) -> Double? { if case .array(let values) = cell["attrs"]["colwidth"], let w = values.first?.number, w != 0 { return w }; return nil }
        for r in 0..<height { for c in 0..<width {
            guard let w = first(rows[r][c]) else { continue }
            if widths[c] == nil || (widths[c] != w && counts[c] == 1) { widths[c] = w; counts[c] = 1 }
            else if widths[c] == w { counts[c] += 1 }
        } }
        guard (0..<width).contains(where: { widths[$0] != nil && counts[$0] < height }) else { return rows }
        var fixed = rows
        for r in 0..<height { for c in 0..<width {
            guard let w = widths[c], rows[r][c]["attrs"]["colwidth"].array.first?.number != w else { continue }
            guard case .object(var fields) = rows[r][c], case .object(var attrs) = fields["attrs"] ?? .object([:]) else { throw ChapterError.unsupported }
            var list = rows[r][c]["attrs"]["colwidth"].array
            if list.isEmpty { list = [.number(0)] }
            list[0] = .number(w); attrs["colwidth"] = .array(list); fields["attrs"] = .object(attrs); fixed[r][c] = .object(fields)
        } }
        return fixed
    }

    /// Replaces one child of the node at `parent`; a container left empty gets the
    /// empty paragraph ProseMirror's replace fitting inserts (block+ content).
    private mutating func replacingChild(_ parent: [Int], at index: Int, with change: (JSONValue) throws -> [JSONValue]) throws {
        func go(_ node: JSONValue, _ rest: ArraySlice<Int>) throws -> JSONValue {
            guard case .object(var fields) = node else { throw ChapterError.unsupported }
            var children = node["content"].array
            if let first = rest.first {
                guard children.indices.contains(first) else { throw ChapterError.unsupported }
                children[first] = try go(children[first], rest.dropFirst())
            } else {
                guard children.indices.contains(index) else { throw ChapterError.unsupported }
                children.replaceSubrange(index...index, with: try change(children[index]))
                if children.isEmpty { children = [.object(["type": .string("paragraph")])] }
            }
            fields["content"] = .array(children); return .object(fields)
        }
        let next = try go(root, ArraySlice(parent))
        self = try RichDocument(json: String(decoding: JSONEncoder().encode(next), as: UTF8.self))
    }
}

public extension VaultRecord {
    func applyingTableCommand(_ command: RichTableCommand, table: [Int], row: Int, column: Int, expected: String, now: Date = Date()) throws -> VaultRecord {
        try editingRichDocument(expected: expected, now: now) { try $0.applyTableCommand(command, table: table, row: row, column: column) }
    }
}
