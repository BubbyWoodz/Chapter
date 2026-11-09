// SPDX-License-Identifier: AGPL-3.0-or-later
// The layout half of the web's video/cards.ts renderTitleCard: the question card cut in before each
// answer in a stitched film. Drawing is platform work; every position, size, line break and the
// shrink-to-four-lines rule are here, with text measurement supplied by the caller.
import Foundation

public enum ChapterTitleCard {
    /// The fallbacks the web uses when a CSS custom property is empty.
    public struct Theme: Equatable, Sendable {
        public let paper, ink, muted, accent, serif, mono: String
        public static let fallback = Theme(paper: "#f4eee2", ink: "#2a2521", muted: "#a99f8e", accent: "#b0563a", serif: "Georgia, serif", mono: "ui-monospace, monospace")
    }
    public struct Line: Equatable, Sendable { public let text: String, x: Double, baseline: Double }
    public struct Layout: Equatable, Sendable {
        /// Question font: weight 500, this many px, the theme's serif.
        public let fontSize: Double
        public let lines: [Line]
        /// The accent rule: from (x0, y) to (x1, y), this thick.
        public let ruleY: Double, ruleX0: Double, ruleX1: Double, ruleWidth: Double
        /// The "n / total" counter in the theme's mono face.
        public let counter: String, counterSize: Double, counterX: Double, counterBaseline: Double
    }

    /// `wrap`: greedy, against a measured width; a word wider than the line is never broken.
    static func wrap(_ text: String, maxWidth: Double, width: (String) -> Double) -> [String] {
        let words = text.unicodeScalars.split(whereSeparator: { EntryLinkAuthoring.ecmaWhitespace.contains($0) }).map { String(String.UnicodeScalarView($0)) }
        var lines: [String] = [], line = ""
        for word in words {
            let next = line.isEmpty ? word : line + " " + word
            if !line.isEmpty && width(next) > maxWidth { lines.append(line); line = word } else { line = next }
        }
        if !line.isEmpty { lines.append(line) }
        return lines
    }

    /// `renderTitleCard`'s layout. `measure(text, px)` is the width of `text` in the serif at `px`.
    public static func layout(text: String, n: Double, total: Double, width: Double, height: Double,
                              measure: (String, Double) -> Double) -> Layout {
        let margin = JS.round(width * 0.11)
        let maxWidth = width - margin * 2
        var size = JS.round(height * 0.085)
        let minSize = JS.round(height * 0.04)
        var lines: [String] = []
        while true {
            let px = size
            lines = wrap(text, maxWidth: maxWidth) { measure($0, px) }
            if lines.count <= 4 || size <= minSize { break }
            size -= 2
        }
        if lines.count > 4 { lines = Array(lines.prefix(3)) + [lines[3] + "…"] }
        let lineHeight = JS.round(size * 1.32)
        let blockHeight = Double(lines.count) * lineHeight
        var y = JS.round((height - blockHeight) / 2 + lineHeight * 0.78)
        var placed: [Line] = []
        for line in lines { placed.append(Line(text: line, x: margin, baseline: y)); y += lineHeight }
        let ruleY = y - lineHeight + JS.round(size * 0.62)
        let ruleWidth = JS.max(2, JS.round(height * 0.005))
        let counter = JSValue.numberString(n) + " / " + JSValue.numberString(total)
        return Layout(fontSize: size, lines: placed, ruleY: ruleY, ruleX0: margin, ruleX1: margin + JS.round(width * 0.09), ruleWidth: ruleWidth,
                      counter: counter, counterSize: JS.round(height * 0.033), counterX: margin, counterBaseline: ruleY + JS.round(height * 0.075))
    }
}
