// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

/// Read-only grid for an original TipTap/ProseMirror table. Mirrors the actual
/// prosemirror-tables `findWidth`/`computeMap` (colspan, rowspan, collisions,
/// overlong rowspans, missing cells). Never rewrites the document.
public struct RichTableLayout: Equatable {
    public struct Cell: Equatable {
        public let path: [Int]       // document path of the cell node
        public let row: Int, column: Int, rowSpan: Int, columnSpan: Int
        public let header: Bool
    }
    public let width: Int, height: Int
    /// 0 = empty grid position, otherwise 1-based cell ordinal in document order.
    public let map: [Int]
    public let cells: [Cell]
    /// prosemirror-tables problem kinds, in the order the original reports them.
    public let problems: [String]
    /// Column widths in points where every cell agrees (TipTap `colwidth`).
    public let columnWidths: [Double?]

    static let maxSpan = 1000, maxPositions = 100_000
    static func span(_ value: JSONValue, _ key: String) -> Int? {
        switch value["attrs"][key] {
        case .null: return 1
        case .number(let n): guard n.isFinite, n == n.rounded(), n >= 1, n <= Double(maxSpan) else { return nil }; return Int(n)
        default: return nil
        }
    }
    /// nil = not a grid the original would lay out sanely (fractional/zero/huge
    /// spans, non-cell children): callers render the honest simplified fallback.
    public init?(table: RichNode) {
        guard table.type == "table" else { return nil }
        let rows = table.children
        guard rows.allSatisfy({ $0.type == "tableRow" && $0.children.allSatisfy { ["tableCell", "tableHeader"].contains($0.type) } }) else { return nil }
        var spans: [[(Int, Int)]] = []
        for row in rows {
            var line: [(Int, Int)] = []
            for cell in row.children { guard let c = Self.span(cell.value, "colspan"), let r = Self.span(cell.value, "rowspan") else { return nil }; line.append((c, r)) }
            spans.append(line)
        }
        // findWidth
        var width = -1, hasRowSpan = false
        for (rowIndex, line) in spans.enumerated() {
            var rowWidth = 0
            if hasRowSpan { for j in 0..<rowIndex { for (c, r) in spans[j] where j + r > rowIndex { rowWidth += c } } }
            for (c, r) in line { rowWidth += c; if r > 1 { hasRowSpan = true } }
            width = width == -1 ? rowWidth : max(width, rowWidth)
        }
        let height = rows.count
        width = max(width, 0)
        guard width * height <= Self.maxPositions else { return nil }
        var map = [Int](repeating: 0, count: width * height), problems: [String] = [], mapPos = 0, ordinal = 0
        var cells: [Cell] = []
        for (rowIndex, line) in spans.enumerated() {
            var i = 0
            while true {
                while mapPos < map.count && map[mapPos] != 0 { mapPos += 1 }
                if i == line.count { break }
                let (colspan, rowspan) = line[i]; ordinal += 1
                var collided = false
                for h in 0..<rowspan {
                    if h + rowIndex >= height { problems.append("overlong_rowspan"); break }
                    let start = mapPos + h * width
                    for w in 0..<colspan {
                        // JS assigns past the end too; such a slot is never 0 here.
                        if start + w < map.count, map[start + w] == 0 { map[start + w] = ordinal } else { problems.append("collision"); collided = true }
                    }
                }
                let node = rows[rowIndex].children[i]
                let column = width == 0 ? 0 : mapPos % width, top = width == 0 ? rowIndex : mapPos / width
                // A collided cell has no reliable rectangle: render it in its first slot only.
                cells.append(Cell(path: node.path, row: top, column: column, rowSpan: collided ? 1 : min(rowspan, height - top), columnSpan: collided ? 1 : min(colspan, max(width - column, 1)), header: node.type == "tableHeader"))
                mapPos += colspan; i += 1
            }
            let expected = (rowIndex + 1) * width; var missing = 0
            while mapPos < expected { if map[mapPos] == 0 { missing += 1 }; mapPos += 1 }
            if missing > 0 { problems.append("missing") }
        }
        if width == 0 || height == 0 { problems.append("zero_sized") }
        // Agreed widths only; disagreement shows natural widths (never guesses).
        var widths = [Double?](repeating: nil, count: width), conflicted = Set<Int>()
        for cell in cells {
            guard case .array(let values) = table.childAt(cell.path)?["attrs"]["colwidth"] else { continue }
            for (w, value) in values.enumerated() where w < cell.columnSpan {
                guard case .number(let n) = value, n.isFinite, n > 0, n <= 10_000 else { continue }
                let col = cell.column + w; guard col < width else { continue }
                if let existing = widths[col], existing != n { conflicted.insert(col) } else { widths[col] = n }
            }
        }
        for col in conflicted { widths[col] = nil }
        self.width = width; self.height = height; self.map = map; self.cells = cells; self.problems = problems; self.columnWidths = widths
    }
}
public extension RichNode {
    /// Child value at an absolute document path that lies under this node.
    func childAt(_ absolute: [Int]) -> JSONValue? {
        guard absolute.count >= path.count, Array(absolute.prefix(path.count)) == path else { return nil }
        var node = value
        for index in absolute.dropFirst(path.count) { guard node["content"].array.indices.contains(index) else { return nil }; node = node["content"].array[index] }
        return node
    }
}
