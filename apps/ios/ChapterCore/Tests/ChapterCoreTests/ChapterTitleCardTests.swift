// SPDX-License-Identifier: AGPL-3.0-or-later
import XCTest
@testable import ChapterCore

/// video/cards.ts renderTitleCard, replayed: the web function drew into a recording mock canvas
/// (scripts/native-cards-vectors.ts) with the same width model this test measures with.
final class ChapterTitleCardTests: XCTestCase {
    /// Space 0.25em, ASCII 0.5em, anything else 1em, per code point.
    private func widthOf(_ text: String, _ px: Double) -> Double {
        text.unicodeScalars.reduce(0) { $0 + ($1 == " " ? 0.25 : $1.value < 128 ? 0.5 : 1) * px }
    }
    private func items(_ v: JSValue?) -> [JSValue] { if case .array(let a)? = v { return a }; return [] }
    private func num(_ v: JSValue?) -> Double { if case .number(let x)? = v { return x }; return .nan }

    func testTitleCardLayoutMatchesTheWebDrawing() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "title-cards", withExtension: "json"))
        let f = try JSValue.parse(String(decoding: try Data(contentsOf: url), as: UTF8.self))
        let theme = ChapterTitleCard.Theme.fallback, t = f.get("theme")
        XCTAssertEqual([theme.paper, theme.ink, theme.muted, theme.accent, theme.serif, theme.mono].map(JSValue.string),
                       ["paper", "ink", "muted", "accent", "serif", "mono"].map { t?.get($0) ?? .null })
        let cases = items(f.get("cases"))
        XCTAssertEqual(cases.count, 91)
        for (k, c) in cases.enumerated() {
            let w = num(c.get("width")), h = num(c.get("height"))
            let l = ChapterTitleCard.layout(text: c.get("text")!.string!, n: num(c.get("n")), total: num(c.get("total")), width: w, height: h, measure: widthOf)
            func n(_ x: Double) -> JSValue { .number(x) }
            var ops: [JSValue] = [.object([("op", .string("rect")), ("x", n(0)), ("y", n(0)), ("w", n(w)), ("h", n(h)), ("style", .string(theme.paper))])]
            let font = "500 " + JSValue.numberString(l.fontSize) + "px " + theme.serif
            for line in l.lines {
                ops.append(.object([("op", .string("text")), ("text", .string(line.text)), ("x", n(line.x)), ("y", n(line.baseline)), ("font", .string(font)),
                                    ("style", .string(theme.ink)), ("align", .string("start")), ("baseline", .string("alphabetic"))]))
            }
            ops.append(.object([("op", .string("line")), ("path", .array([.array([n(l.ruleX0), n(l.ruleY)]), .array([n(l.ruleX1), n(l.ruleY)])])), ("width", n(l.ruleWidth)), ("style", .string(theme.accent))]))
            ops.append(.object([("op", .string("text")), ("text", .string(l.counter)), ("x", n(l.counterX)), ("y", n(l.counterBaseline)),
                                ("font", .string(JSValue.numberString(l.counterSize) + "px " + theme.mono)), ("style", .string(theme.muted)), ("align", .string("start")), ("baseline", .string("alphabetic"))]))
            XCTAssertEqual(JSValue.array(ops), c.get("ops"), "card \(k)")
        }
    }
}
