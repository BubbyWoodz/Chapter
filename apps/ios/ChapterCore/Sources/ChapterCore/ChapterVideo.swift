// SPDX-License-Identifier: AGPL-3.0-or-later
// Ports of the web's pure video logic: video/timeline.ts (frame-exact film layout and output size)
// and editor/videointerviewData.ts (defensive session coercion, answered/stale rules and the
// out-of-editor transcript/film write-back), with JavaScript's semantics where they leak into the
// result: Math.round/max/min with NaN, Number(), and object spread of non-objects.
import Foundation

public enum ChapterFilmTimeline {
    /// How long each question card holds before its answer.
    public static let cardSeconds = 2.5
    /// The film's canonical output clock.
    public static let fps = 30.0

    public struct Segment: Equatable, Sendable {
        public enum Kind: String, Sendable { case card, clip }
        public let kind: Kind, index: Int, startS: Double, durationS: Double, frames: Double
    }
    public struct Timeline: Equatable, Sendable { public let segments: [Segment], totalS: Double, totalFrames: Double }

    /// `planTimeline`: one card plus one answer per question, counted in whole output frames.
    public static func plan(_ clipDurations: [Double], fps: Double = fps, cardSeconds: Double = cardSeconds) -> Timeline {
        let cardFrames = JS.max(1, JS.round(cardSeconds * fps))
        var segments: [Segment] = [], frame = 0.0
        for (index, seconds) in clipDurations.enumerated() {
            segments.append(Segment(kind: .card, index: index, startS: frame / fps, durationS: cardFrames / fps, frames: cardFrames))
            frame += cardFrames
            let clipFrames = JS.max(1, JS.round(seconds * fps))
            segments.append(Segment(kind: .clip, index: index, startS: frame / fps, durationS: clipFrames / fps, frames: clipFrames))
            frame += clipFrames
        }
        return Timeline(segments: segments, totalS: frame / fps, totalFrames: frame)
    }
    /// `estimateSeconds`: the rough length shown before a render starts.
    public static func estimateSeconds(_ clipDurations: [Double], cardSeconds: Double = cardSeconds) -> Double {
        clipDurations.reduce(0, +) + Double(clipDurations.count) * cardSeconds
    }
    /// `canonicalSize`: short edge 720, long edge clamped to 640…1280, both even.
    public static func canonicalSize(displayWidth w: Double, displayHeight h: Double) -> (width: Double, height: Double) {
        func even(_ n: Double) -> Double { JS.max(2, (n / 2).rounded(.down) * 2) }
        let landscape = w >= h, short = 720.0
        let ratio = landscape ? w / h : h / w
        let long = JS.min(1280, JS.max(640, JS.round(short * ratio)))
        return landscape ? (even(long), even(short)) : (even(short), even(long))
    }
}

public enum ChapterVideoInterview {
    public static let nodeType = "videoInterview"

    public struct Clip: Equatable, Sendable {
        public let id: String, mime: String, bytes: Double, durationMs: Double?, name: String?, width: Double?, height: Double?, createdAt: Double
        public var kind: String { "video" }
    }
    public struct Card: Equatable, Sendable {
        public let q: String, clip: Clip?, transcript: String?, dropped: Bool
        /// `isAnswered`: the clip is present, or was dropped after rendering, or a transcript survives.
        public var isAnswered: Bool { clip != nil || dropped || transcript != nil }
    }
    public struct Session: Equatable, Sendable {
        public let sessionId: String, typeName: String, cards: [Card], film: Clip?, renderedAt: Double?, lang: String?
        /// `videoInterviewAttachments`: the clips in card order, then the film.
        public var attachments: [Clip] { cards.compactMap(\.clip) + (film.map { [$0] } ?? []) }
        /// `isFilmStale`: some answer clip is newer than the render.
        public var isFilmStale: Bool {
            guard film != nil, let rendered = renderedAt else { return false }
            return cards.contains { ($0.clip?.createdAt).map { $0 > rendered } ?? false }
        }
    }

    static func coerceClip(_ raw: JSValue?) -> Clip? {
        guard let raw, JSValue.truthy(raw), case .object = raw else { return nil }
        guard case .string(let id)? = raw.get("id"), !id.isEmpty else { return nil }
        func num(_ k: String) -> Double? { if case .number(let n)? = raw.get(k) { return n }; return nil }
        func orNil(_ k: String) -> JSValue? { let v = raw.get(k); return v == .null ? nil : v }
        let name: String? = { if case .string(let s)? = raw.get("name"), !s.isEmpty { return s }; return nil }()
        return Clip(id: id, mime: orNil("mime").map(JSValue.toString) ?? "video/webm", bytes: orNil("bytes").map(JS.number) ?? 0,
                    durationMs: num("durationMs"), name: name, width: num("width"), height: num("height"),
                    createdAt: orNil("createdAt").map(JS.number) ?? 0)
    }

    /// `coerceVideoInterview(attrs)`: nil when malformed; throws on null attrs like the web.
    public static func coerce(_ attrs: JSValue) throws -> Session? {
        guard case .array(let raw)? = try JSValue.prop(attrs, "cards"), !raw.isEmpty else { return nil }
        let cards = raw.map { c -> Card in
            let o: JSValue = { switch c { case .object, .array: return c; default: return .object([]) } }()
            func text(_ k: String, nonEmpty: Bool) -> String? { if case .string(let s)? = o.get(k), !(nonEmpty && s.isEmpty) { return s }; return nil }
            return Card(q: text("q", nonEmpty: false) ?? "", clip: coerceClip(o.get("clip")), transcript: text("transcript", nonEmpty: true), dropped: o.get("dropped") == .bool(true))
        }
        func text(_ k: String) -> String? { if case .string(let s)? = attrs.get(k) { return s }; return nil }
        let renderedAt: Double? = { if case .number(let n)? = attrs.get("renderedAt") { return n }; return nil }()
        return Session(sessionId: text("sessionId") ?? "", typeName: text("typeName") ?? "", cards: cards, film: coerceClip(attrs.get("film")),
                       renderedAt: renderedAt, lang: text("lang").flatMap { $0.isEmpty ? nil : $0 })
    }

    /// `setTranscriptAttr`: write one answer's transcript into every node with this session id, on a
    /// stored bodyJson. nil when the body is empty or unparsable or nothing matched; throws where the
    /// web's walk throws (a null node, a non-array `content`).
    public static func setTranscript(bodyJSON: String?, sessionId: String, cardIndex: Int, transcript: String) throws -> String? {
        try rewrite(bodyJSON, sessionId) { attrs in
            guard case .array(var cards)? = attrs.get("cards"), cardIndex >= 0, cardIndex < cards.count else { return false }
            cards[cardIndex] = .object(JS.setting(JS.spread(cards[cardIndex]), "transcript", .string(transcript)))
            attrs = .object(JS.setting(JS.spread(attrs), "cards", .array(cards)))
            return true
        }
    }
    /// `setFilmAttr`: write a rendered film (a MediaAttachment object) and its render time.
    public static func setFilm(bodyJSON: String?, sessionId: String, film: JSValue, at: Double) throws -> String? {
        try rewrite(bodyJSON, sessionId) { attrs in
            attrs = .object(JS.setting(JS.setting(JS.spread(attrs), "film", .object(JS.spread(film))), "renderedAt", .number(at)))
            return true
        }
    }

    static func rewrite(_ bodyJSON: String?, _ sessionId: String, _ edit: (inout JSValue) -> Bool) throws -> String? {
        guard let bodyJSON, !bodyJSON.isEmpty, !sessionId.isEmpty, var doc = try? JSValue.parse(bodyJSON) else { return nil }
        var hit = false
        func walk(_ node: inout JSValue) throws {
            guard node != .null else { throw JSValue.TypeError() }
            guard case .object(var fields) = node else { return }
            if node.get("type") == .string(nodeType), JSValue.opt(node.get("attrs"), "sessionId") == .string(sessionId),
               let i = fields.lastIndex(where: { $0.0 == "attrs" }) {
                var attrs = fields[i].1
                if edit(&attrs) { hit = true }
                fields[i].1 = attrs
            }
            if let i = fields.lastIndex(where: { $0.0 == "content" }) {
                switch fields[i].1 {
                case .null: break
                case .array(var children):
                    for j in children.indices { try walk(&children[j]) }
                    fields[i].1 = .array(children)
                default: throw JSValue.TypeError()
                }
            }
            node = .object(fields)
        }
        try walk(&doc)
        return hit ? doc.stringify() : nil
    }
}

/// The JavaScript operations these ports need.
enum JS {
    static func round(_ x: Double) -> Double { DayOneArchive.jsRound(x) }
    /// `Math.max(a, b)`: NaN wins, and +0 beats -0.
    static func max(_ a: Double, _ b: Double) -> Double {
        if a.isNaN || b.isNaN { return .nan }
        if a == b { return a.sign == .minus ? b : a }
        return a > b ? a : b
    }
    static func min(_ a: Double, _ b: Double) -> Double {
        if a.isNaN || b.isNaN { return .nan }
        if a == b { return a.sign == .minus ? a : b }
        return a < b ? a : b
    }
    /// `Number(v)`.
    static func number(_ v: JSValue) -> Double {
        switch v {
        case .number(let n): return n
        case .bool(let b): return b ? 1 : 0
        case .null: return 0
        case .string(let s): return number(s)
        case .array: return number(JSValue.toString(v))
        case .object: return .nan
        }
    }
    /// StringToNumber: trimmed decimal or Infinity, or an unsigned 0x/0o/0b integer; otherwise NaN.
    static func number(_ s: String) -> Double {
        let t = Array(s.trimmingCharacters(in: EntryLinkAuthoring.ecmaWhitespace).unicodeScalars)
        if t.isEmpty { return 0 }
        func isDigit(_ c: Unicode.Scalar, _ radix: Int) -> Bool { c.isASCII && Int(String(c), radix: radix) != nil }
        if t.count > 2, t[0] == "0", let radix = ["x": 16, "X": 16, "o": 8, "O": 8, "b": 2, "B": 2][Character(t[1])] {
            let digits = t[2...]
            guard digits.allSatisfy({ isDigit($0, radix) }) else { return .nan }
            if radix == 16 { return Double("0x" + String(String.UnicodeScalarView(digits))) ?? .nan }
            // Exact as hex, so strtod rounds the whole integer once, like JavaScript.
            var bits = digits.flatMap { d -> [Bool] in let v = Int(String(d), radix: radix)!; let w = radix == 8 ? 3 : 1; return (0..<w).reversed().map { v >> $0 & 1 == 1 } }
            while bits.count % 4 != 0 { bits.insert(false, at: 0) }
            let hex = stride(from: 0, to: bits.count, by: 4).map { i in String(bits[i..<i + 4].reduce(0) { $0 * 2 + ($1 ? 1 : 0) }, radix: 16) }.joined()
            return Double("0x" + hex) ?? .nan
        }
        var i = 0, negative = false
        if t[0] == "+" || t[0] == "-" { negative = t[0] == "-"; i = 1 }
        let rest = String(String.UnicodeScalarView(t[i...]))
        if rest == "Infinity" { return negative ? -.infinity : .infinity }
        var intPart = "", frac = "", exp = ""
        var j = rest.unicodeScalars.startIndex; let u = rest.unicodeScalars
        while j < u.endIndex, isDigit(u[j], 10) { intPart.unicodeScalars.append(u[j]); j = u.index(after: j) }
        if j < u.endIndex, u[j] == "." { j = u.index(after: j); while j < u.endIndex, isDigit(u[j], 10) { frac.unicodeScalars.append(u[j]); j = u.index(after: j) } }
        if intPart.isEmpty && frac.isEmpty { return .nan }
        if j < u.endIndex, u[j] == "e" || u[j] == "E" {
            j = u.index(after: j)
            if j < u.endIndex, u[j] == "+" || u[j] == "-" { exp.unicodeScalars.append(u[j]); j = u.index(after: j) }
            var expDigits = ""
            while j < u.endIndex, isDigit(u[j], 10) { expDigits.unicodeScalars.append(u[j]); j = u.index(after: j) }
            if expDigits.isEmpty { return .nan }
            exp = "e" + exp + expDigits
        }
        guard j == u.endIndex else { return .nan }
        let literal = (negative ? "-" : "") + (intPart.isEmpty ? "0" : intPart) + (frac.isEmpty ? "" : "." + frac) + exp
        return Double(literal) ?? .nan
    }
    /// The own enumerable properties `{...v}` copies: an object's fields, an array's or a string's
    /// indices (one UTF-16 unit each); nothing for other primitives.
    static func spread(_ v: JSValue) -> [(String, JSValue)] {
        switch v {
        case .object(let o): return o
        case .array(let a): return a.enumerated().map { (String($0.offset), $0.element) }
        case .string(let s): return s.utf16.enumerated().map { (String($0.offset), .string(String(utf16CodeUnits: [$0.element], count: 1))) }
        default: return []
        }
    }
    /// `o[key] = value`: an existing key keeps its position.
    static func setting(_ fields: [(String, JSValue)], _ key: String, _ value: JSValue) -> [(String, JSValue)] {
        var out = fields
        if let i = out.firstIndex(where: { $0.0 == key }) { out[i].1 = value } else { out.append((key, value)) }
        return out
    }
}
