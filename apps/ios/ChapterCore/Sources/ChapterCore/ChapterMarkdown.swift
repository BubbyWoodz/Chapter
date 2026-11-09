// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

/// A JSON value with JavaScript object semantics: keys keep their `JSON.parse` order
/// (a duplicate key keeps its first position and takes the last value), and
/// `JSON.stringify` writes array-index keys first, ascending. Strings are Swift
/// strings, so a lone surrogate escape (`\ud800`) becomes U+FFFD, as everywhere else
/// a vault record is decoded.
public indirect enum JSValue: Equatable, Sendable {
    case object([(String, JSValue)]), array([JSValue]), string(String), number(Double), bool(Bool), null
    public static func == (a: JSValue, b: JSValue) -> Bool {
        switch (a, b) {
        case (.object(let x), .object(let y)): return x.count == y.count && zip(x, y).allSatisfy { $0.0 == $1.0 && $0.1 == $1.1 }
        case (.array(let x), .array(let y)): return x == y
        case (.string(let x), .string(let y)): return x == y
        case (.number(let x), .number(let y)): return x == y
        case (.bool(let x), .bool(let y)): return x == y
        case (.null, .null): return true
        default: return false
        }
    }
    struct TypeError: Error {}

    // MARK: JSON.parse (strict ECMA-404 grammar, like JavaScript)
    public static func parse(_ text: String) throws -> JSValue {
        var p = Parser(s: Array(text.unicodeScalars)); p.ws()
        let v = try p.value(); p.ws()
        guard p.i == p.s.count else { throw TypeError() }
        return v
    }
    struct Parser {
        let s: [Unicode.Scalar]; var i = 0
        mutating func ws() { while i < s.count, [" ", "\t", "\n", "\r"].contains(s[i]) { i += 1 } }
        mutating func lit(_ w: String) throws { for c in w.unicodeScalars { guard i < s.count, s[i] == c else { throw TypeError() }; i += 1 } }
        mutating func value() throws -> JSValue {
            guard i < s.count else { throw TypeError() }
            switch s[i] {
            case "{":
                i += 1; ws(); var fields: [(String, JSValue)] = []; var index: [String: Int] = [:]
                if i < s.count, s[i] == "}" { i += 1; return .object([]) }
                while true {
                    guard i < s.count, s[i] == "\"" else { throw TypeError() }
                    let k = try string(); ws(); try lit(":"); ws(); let v = try value()
                    if let at = index[k] { fields[at].1 = v } else { index[k] = fields.count; fields.append((k, v)) }
                    ws(); guard i < s.count else { throw TypeError() }
                    if s[i] == "," { i += 1; ws(); continue }
                    if s[i] == "}" { i += 1; return .object(fields) }
                    throw TypeError()
                }
            case "[":
                i += 1; ws(); var items: [JSValue] = []
                if i < s.count, s[i] == "]" { i += 1; return .array([]) }
                while true {
                    items.append(try value()); ws(); guard i < s.count else { throw TypeError() }
                    if s[i] == "," { i += 1; ws(); continue }
                    if s[i] == "]" { i += 1; return .array(items) }
                    throw TypeError()
                }
            case "\"": return .string(try string())
            case "t": try lit("true"); return .bool(true)
            case "f": try lit("false"); return .bool(false)
            case "n": try lit("null"); return .null
            default: return try number()
            }
        }
        mutating func digits() -> Int { let start = i; while i < s.count, ("0"..."9").contains(s[i]) { i += 1 }; return i - start }
        mutating func number() throws -> JSValue {
            let start = i
            if i < s.count, s[i] == "-" { i += 1 }
            guard i < s.count else { throw TypeError() }
            if s[i] == "0" { i += 1 } else { guard digits() > 0 else { throw TypeError() } }
            if i < s.count, s[i] == "." { i += 1; guard digits() > 0 else { throw TypeError() } }
            if i < s.count, s[i] == "e" || s[i] == "E" { i += 1; if i < s.count, s[i] == "+" || s[i] == "-" { i += 1 }; guard digits() > 0 else { throw TypeError() } }
            var text = ""; text.unicodeScalars.append(contentsOf: s[start..<i])
            guard let d = Double(text) else { throw TypeError() }
            return .number(d)
        }
        mutating func hex4() throws -> UInt32 {
            guard i + 4 <= s.count, let v = UInt32(String(String.UnicodeScalarView(s[i..<i + 4])), radix: 16) else { throw TypeError() }
            i += 4; return v
        }
        mutating func string() throws -> String {
            i += 1; var out = String.UnicodeScalarView()
            while true {
                guard i < s.count else { throw TypeError() }
                let c = s[i]; i += 1
                if c == "\"" { return String(out) }
                if c.value < 0x20 { throw TypeError() }
                guard c == "\\" else { out.append(c); continue }
                guard i < s.count else { throw TypeError() }
                let e = s[i]; i += 1
                switch e {
                case "\"": out.append("\""); case "\\": out.append("\\"); case "/": out.append("/")
                case "b": out.append("\u{8}"); case "f": out.append("\u{C}"); case "n": out.append("\n"); case "r": out.append("\r"); case "t": out.append("\t")
                case "u":
                    var u = try hex4()
                    if (0xD800...0xDBFF).contains(u), i + 6 <= s.count, s[i] == "\\", s[i + 1] == "u" {
                        let save = i; i += 2
                        let lo = try hex4()
                        if (0xDC00...0xDFFF).contains(lo) { u = 0x10000 + ((u - 0xD800) << 10) + (lo - 0xDC00) } else { i = save }
                    }
                    out.append(Unicode.Scalar(u) ?? "\u{FFFD}")
                default: throw TypeError()
                }
            }
        }
    }

    // MARK: JSON.stringify (no indentation)
    static func isArrayIndex(_ k: String) -> Bool {
        guard k == "0" || (k.first.map { ("1"..."9").contains($0) } ?? false), k.allSatisfy({ ("0"..."9").contains($0) }), k.count <= 10, let n = UInt64(k) else { return false }
        return n <= 4_294_967_294
    }
    public static func ordered(_ fields: [(String, JSValue)]) -> [(String, JSValue)] {
        fields.filter { isArrayIndex($0.0) }.sorted { UInt64($0.0)! < UInt64($1.0)! } + fields.filter { !isArrayIndex($0.0) }
    }
    public func stringify() -> String {
        switch self {
        case .null: return "null"
        case .bool(let b): return b ? "true" : "false"
        case .number(let n): return n.isFinite ? JSValue.numberString(n) : "null"
        case .string(let s): return JSValue.quote(s)
        case .array(let a): return "[" + a.map { $0.stringify() }.joined(separator: ",") + "]"
        case .object(let o): return "{" + JSValue.ordered(o).map { JSValue.quote($0.0) + ":" + $0.1.stringify() }.joined(separator: ",") + "}"
        }
    }
    static func quote(_ s: String) -> String {
        var out = "\""
        for u in s.unicodeScalars {
            switch u {
            case "\"": out += "\\\""; case "\\": out += "\\\\"; case "\u{8}": out += "\\b"; case "\u{C}": out += "\\f"
            case "\n": out += "\\n"; case "\r": out += "\\r"; case "\t": out += "\\t"
            default:
                if u.value < 0x20 { let h = String(u.value, radix: 16); out += "\\u" + String(repeating: "0", count: 4 - h.count) + h } else { out.unicodeScalars.append(u) }
            }
        }
        return out + "\""
    }
    /// JavaScript `Number::toString` (shortest round-trip digits).
    public static func numberString(_ x: Double) -> String {
        if x.isNaN { return "NaN" }
        if x == 0 { return "0" }
        if x.isInfinite { return x < 0 ? "-Infinity" : "Infinity" }
        if x < 0 { return "-" + numberString(-x) }
        // Swift's description is shortest round-trip too; recover its digits and exponent.
        let d = "\(x)"
        let parts = d.split(separator: "e", maxSplits: 1)
        let mantissa = String(parts[0]), exp10 = parts.count > 1 ? Int(parts[1].replacingOccurrences(of: "+", with: ""))! : 0
        let dot = mantissa.firstIndex(of: ".")
        let intPart = dot.map { String(mantissa[..<$0]) } ?? mantissa, frac = dot.map { String(mantissa[mantissa.index(after: $0)...]) } ?? ""
        var digits = intPart + frac
        var n = intPart.count + exp10   // value = 0.digits × 10^n
        while digits.hasPrefix("0") { digits.removeFirst(); n -= 1 }
        while digits.hasSuffix("0") { digits.removeLast() }
        let k = digits.count
        if k <= n && n <= 21 { return digits + String(repeating: "0", count: n - k) }
        if 0 < n && n <= 21 { return String(digits.prefix(n)) + "." + String(digits.dropFirst(n)) }
        if -6 < n && n <= 0 { return "0." + String(repeating: "0", count: -n) + digits }
        let e = n - 1, sign = e < 0 ? "-" : "+"
        return String(digits.prefix(1)) + (k > 1 ? "." + String(digits.dropFirst()) : "") + "e" + sign + String(abs(e))
    }

    // MARK: JavaScript property access, truthiness and ToString
    /// `v.key` (throws on undefined/null like JavaScript); primitives and arrays have none of the keys used here.
    func get(_ key: String) -> JSValue? { if case .object(let o) = self { return o.last { $0.0 == key }?.1 }; return nil }
    static func prop(_ v: JSValue?, _ key: String) throws -> JSValue? {
        guard let v, v != .null else { throw TypeError() }
        return v.get(key)
    }
    /// `v?.key`
    static func opt(_ v: JSValue?, _ key: String) -> JSValue? { guard let v, v != .null else { return nil }; return v.get(key) }
    static func truthy(_ v: JSValue?) -> Bool {
        switch v { case nil, .null?: return false; case .bool(let b)?: return b; case .number(let n)?: return n != 0 && !n.isNaN; case .string(let s)?: return !s.isEmpty; default: return true }
    }
    static func toString(_ v: JSValue) -> String {
        switch v {
        case .string(let s): return s
        case .number(let n): return numberString(n)
        case .bool(let b): return b ? "true" : "false"
        case .null: return "null"
        case .object: return "[object Object]"
        case .array(let a): return a.map { $0 == .null ? "" : toString($0) }.joined(separator: ",")
        }
    }
    var string: String? { if case .string(let s) = self { return s }; return nil }
    /// Converted for the archive's JSON (key order is irrelevant there; non-finite numbers become null, like JSON.stringify).
    public var jsonValue: JSONValue {
        switch self {
        case .object(let o): var d: [String: JSONValue] = [:]; for (k, v) in o { d[k] = v.jsonValue }; return .object(d)
        case .array(let a): return .array(a.map(\.jsonValue))
        case .string(let s): return .string(s)
        case .number(let n): return .number(n)
        case .bool(let b): return .bool(b)
        case .null: return .null
        }
    }
}

/// Port of the serializing half of the web editor/markdown.ts (`docToMarkdown`), the
/// `markdown` field of a journal export. Every JavaScript failure mode (a property read
/// on null, `.map` on a non-array, `.replace` on a non-string) throws here too, and the
/// export then falls back to the entry text, like the web `safeMarkdown`.
public enum ChapterMarkdown {
    typealias V = JSValue
    struct TypeError: Error {}

    public static func docToMarkdown(_ doc: JSValue) throws -> String {
        let blocks = try list(V.prop(doc, "content")).map { try block($0) }
        var joined = collapseNewlines(blocks.joined(separator: "\n\n"))
        let ws = EntryLinkAuthoring.ecmaWhitespace
        var scalars = Array(joined.unicodeScalars)
        while let f = scalars.first, ws.contains(f) { scalars.removeFirst() }
        while let l = scalars.last, ws.contains(l) { scalars.removeLast() }
        joined = String(String.UnicodeScalarView(scalars))
        return joined + "\n"
    }

    /// `(v ?? [])` then `.map`/`.forEach`: an array, or a TypeError.
    static func list(_ v: V?) throws -> [V] {
        switch v { case nil, .null?: return []; case .array(let a)?: return a; default: throw TypeError() }
    }
    static func collapseNewlines(_ s: String) -> String {
        var out = String.UnicodeScalarView(); var run = 0
        for u in s.unicodeScalars {
            if u == "\n" { run += 1; continue }
            if run > 0 { out.append(contentsOf: Array(repeating: "\n", count: run >= 3 ? 2 : run)); run = 0 }
            out.append(u)
        }
        if run > 0 { out.append(contentsOf: Array(repeating: "\n", count: run >= 3 ? 2 : run)) }
        return String(out)
    }
    static func lines(_ s: String) -> [String] {
        var out: [String] = []; var cur = String.UnicodeScalarView()
        for u in s.unicodeScalars { if u == "\n" { out.append(String(cur)); cur = .init() } else { cur.append(u) } }
        out.append(String(cur)); return out
    }
    static func prefixLines(_ text: String, _ prefix: String) -> String { lines(text).map { prefix + $0 }.joined(separator: "\n") }
    static func escape(_ text: String, _ set: String) -> String {
        var out = String.UnicodeScalarView()
        for u in text.unicodeScalars { if set.unicodeScalars.contains(u) { out.append("\\") }; out.append(u) }
        return String(out)
    }

    static func block(_ node: V, depth: Int = 0) throws -> String {
        let type = try V.prop(node, "type")?.string
        let attrs = { V.opt(try? V.prop(node, "attrs"), $0) }
        switch type {
        case "paragraph": return try inline(V.prop(node, "content"))
        case "heading":
            let n: Double = { if case .number(let n)? = attrs("level") { return n }; return 1 }()
            return String(repeating: "#", count: Int(min(3, max(1, n)).rounded(.towardZero))) + " " + (try inline(V.prop(node, "content")))
        case "blockquote": return prefixLines(try children(node, depth), "> ")
        case "codeBlock":
            let lang = attrs("language")?.string ?? ""
            let text = try list(V.prop(node, "content")).map { c -> String in
                guard try V.prop(c, "type") == .string("text"), let t = c.get("text"), t != .null else { return "" }
                return V.toString(t)
            }.joined()
            let fence = backtickFence(text)
            return "\(fence)\(lang)\n\(text)\n\(fence)"
        case "horizontalRule": return "---"
        case "bulletList": return try listItems(node, depth) { _ in "- " }
        case "orderedList":
            let start: Double = { if case .number(let s)? = attrs("start"), s > 0 { return s }; return 1 }()
            return try listItems(node, depth) { "\(V.numberString(start + Double($0))). " }
        case "taskList":
            return try list(V.prop(node, "content")).map { item in
                try listItem(item, depth, "- [\(V.truthy(V.opt(V.prop(item, "attrs"), "checked")) ? "x" : " ")] ")
            }.joined(separator: "\n")
        case "table": return try table(node)
        case "blockMath": return "$$\n\(attrs("latex")?.string ?? "")\n$$"
        case "mediaAttachment": return jsonFence("mneme:media", node)
        case "mediaGallery": return jsonFence("mneme:gallery", node)
        default: return jsonFence("mneme:node", node)
        }
    }
    static func children(_ node: V, _ depth: Int) throws -> String {
        try list(V.prop(node, "content")).map { try block($0, depth: depth) }.joined(separator: "\n\n")
    }
    static func listItems(_ node: V, _ depth: Int, _ marker: (Int) -> String) throws -> String {
        try list(V.prop(node, "content")).enumerated().map { try listItem($0.element, depth, marker($0.offset)) }.joined(separator: "\n")
    }
    static func listItem(_ item: V, _ depth: Int, _ marker: String) throws -> String {
        let indent = String(repeating: "  ", count: depth), pad = String(repeating: " ", count: marker.utf16.count)
        var parts: [String] = []
        for (idx, child) in try list(V.prop(item, "content")).enumerated() {
            let t = try V.prop(child, "type")
            let isList = t == .string("bulletList") || t == .string("orderedList") || t == .string("taskList")
            let rendered = try block(child, depth: isList ? depth + 1 : depth)
            if idx == 0 && !isList { parts.append(indent + marker + rendered) } else if isList { parts.append(rendered) } else { parts.append(prefixLines(rendered, indent + pad)) }
        }
        if parts.isEmpty { parts.append(indent + marker) }
        return parts.joined(separator: "\n")
    }

    /// `for (const x of v)`: arrays, or a string's code points; anything else is not iterable.
    static func iterate(_ v: V?) throws -> [V] {
        switch v {
        case nil, .null?: return []
        case .array(let a)?: return a
        case .string(let s)?: return s.unicodeScalars.map { .string(String($0)) }
        default: throw TypeError()
        }
    }
    static func tableIsSimple(_ rows: V?) throws -> Bool {
        for row in try iterate(rows) {
            for cell in try iterate(V.prop(row, "content")) {
                let attrs = try V.prop(cell, "attrs")
                if (V.opt(attrs, "colspan") ?? .number(1)) != .number(1) || (V.opt(attrs, "rowspan") ?? .number(1)) != .number(1) { return false }
                switch cell.get("content") ?? .array([]) {
                case .array(let kids):
                    guard kids.count == 1 else { return false }
                    if try V.prop(kids[0], "type") != .string("paragraph") { return false }
                case .null: return false   // `null ?? []` is [] (length 0)
                default: return false      // a string's characters or `undefined` length are never a paragraph
                }
            }
        }
        switch rows { case .array(let a)?: return !a.isEmpty; case .string(let s)?: return !s.utf16.isEmpty; default: return false }
    }
    static func table(_ node: V) throws -> String {
        let rows = try V.prop(node, "content")
        guard try tableIsSimple(rows) else { return jsonFence("mneme:table", node) }
        var out: [String] = []
        for (r, row) in try list(rows).enumerated() {
            let cells = try list(V.prop(row, "content")).map { cell -> String in
                let first: V? = { if case .array(let kids)? = cell.get("content") { return kids.first }; return nil }()
                return escape(try inline(V.opt(first, "content")), "\\|")
            }
            out.append("| \(cells.joined(separator: " | ")) |")
            if r == 0 { out.append("| \(cells.map { _ in "---" }.joined(separator: " | ")) |") }
        }
        return out.joined(separator: "\n")
    }

    static func inline(_ content: V?) throws -> String {
        guard V.truthy(content) else { return "" }
        guard case .array(let nodes)? = content else { throw TypeError() }
        return try nodes.map(inlineNode).joined()
    }
    static func inlineNode(_ node: V) throws -> String {
        let type = try V.prop(node, "type")
        let attrs = { V.opt(node.get("attrs"), $0) }
        switch type {
        case .string("text")?:
            let text = node.get("text").flatMap { $0 == .null ? nil : $0 } ?? .string("")
            return try marks(text, node.get("marks"))
        case .string("hardBreak")?: return "\\\n"
        case .string("inlineMath")?: return "$\(attrs("latex")?.string ?? "")$"
        case .string("entryLink")?: return "[[\(attrs("entryId")?.string ?? "")|\(attrs("label")?.string ?? "")]]"
        default: return ""
        }
    }
    static func marks(_ text: V, _ marksV: V?) throws -> String {
        let marks = try list(marksV)
        let names = try marks.map { try V.prop($0, "type") }
        func has(_ n: String) -> Bool { names.contains { $0 == .string(n) } }
        if has("code") { return "`" + V.toString(text) + "`" }
        guard case .string(let raw) = text else { throw TypeError() }
        var s = escape(raw, "\\`*_~$[]")
        if has("strike") { s = "~~\(s)~~" }
        if has("bold") && has("italic") { s = "***\(s)***" } else if has("bold") { s = "**\(s)**" } else if has("italic") { s = "*\(s)*" }
        let link = marks.first { $0.get("type") == .string("link") }
        if let href = safeHref(V.opt(V.opt(link, "attrs"), "href")) { s = "[\(s)](\(href))" }
        return s
    }
    /// editor/url.ts `safeHref`.
    public static func safeHref(_ v: JSValue?) -> String? {
        guard case .string(let href)? = v else { return nil }
        let cleaned = String(String.UnicodeScalarView(href.unicodeScalars.filter { u in
            !(u.value <= 0x20 || (0x7F...0xA0).contains(u.value) || (0x200B...0x200D).contains(u.value) || u.value == 0xFEFF)
        }))
        guard !cleaned.isEmpty else { return nil }
        let scalars = Array(cleaned.unicodeScalars)
        func letter(_ u: Unicode.Scalar) -> Bool { ("a"..."z").contains(u) || ("A"..."Z").contains(u) }
        guard let first = scalars.first, letter(first) else { return href }
        var i = 1
        while i < scalars.count, letter(scalars[i]) || ("0"..."9").contains(scalars[i]) || "+.-".unicodeScalars.contains(scalars[i]) { i += 1 }
        guard i < scalars.count, scalars[i] == ":" else { return href }
        let scheme = String(String.UnicodeScalarView(scalars[0..<i])).lowercased()
        return ["http", "https", "mailto", "tel"].contains(scheme) ? href : nil
    }
    static func backtickFence(_ text: String) -> String {
        var longest = 0, run = 0
        for u in text.unicodeScalars { if u == "`" { run += 1; longest = max(longest, run) } else { run = 0 } }
        return String(repeating: "`", count: max(3, longest + 1))
    }
    static func jsonFence(_ tag: String, _ node: V) -> String { "```" + tag + "\n" + node.stringify() + "\n```" }
}
