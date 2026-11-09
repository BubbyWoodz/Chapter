// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

/// Port of the web Day One importer's pure parts: import/markdown.ts (`markdownToBlocks`,
/// `splitTitle`) and import/dayone.ts (`parseMomentUrl`, `entryMoments`). Strings are
/// handled as UTF-16 like JavaScript, and every regular expression spells out
/// JavaScript's `\s`, `\d`, `.` and `$` (ICU's differ, for example on U+0085 and U+FEFF).
public enum ChapterDayOne {
    public static let mediaRef = "__dayoneMedia"
    typealias U = [UInt16]

    static let jsSpace = "\\t\\n\\u000B\\f\\r \\u00A0\\u1680\\u2000-\\u200A\\u2028\\u2029\\u202F\\u205F\\u3000\\uFEFF"
    static func re(_ pattern: String) -> NSRegularExpression {
        let p = pattern.replacingOccurrences(of: "\\s", with: "[\(jsSpace)]").replacingOccurrences(of: "\\S", with: "[^\(jsSpace)]").replacingOccurrences(of: "\\d", with: "[0-9]")
        return try! NSRegularExpression(pattern: p)
    }
    /// `s.match(re)` (anchored at the start): capture groups as Swift strings, nil when unmatched.
    static func match(_ r: NSRegularExpression, _ s: String) -> [String?]? {
        let ns = s as NSString
        guard let m = r.firstMatch(in: s, options: [.anchored], range: NSRange(location: 0, length: ns.length)) else { return nil }
        return (0..<m.numberOfRanges).map { m.range(at: $0).location == NSNotFound ? nil : ns.substring(with: m.range(at: $0)) }
    }
    static func str(_ u: ArraySlice<UInt16>) -> String { String(decoding: Array(u), as: UTF16.self) }
    static func trim(_ s: String) -> String {
        var u = Array(s.utf16)
        func ws(_ c: UInt16) -> Bool { ChapterSearch.isWhitespace(c) }
        while let f = u.first, ws(f) { u.removeFirst() }
        while let l = u.last, ws(l) { u.removeLast() }
        return str(u[...])
    }

    // MARK: dayone.ts
    public enum MomentKind: String, Sendable { case image, video, audio, file }
    static let momentURL = re("dayone-moment:/(?:/)?(?:(video|audio|pdfAttachment)/)?([A-Za-z0-9-]+)")
    public static func parseMomentURL(_ url: String) -> (kind: MomentKind, identifier: String)? {
        guard let m = match(momentURL, url), let id = m[2] else { return nil }
        let kind: MomentKind = m[1] == "video" ? .video : m[1] == "audio" ? .audio : m[1] == "pdfAttachment" ? .file : .image
        return (kind, id)
    }

    // MARK: markdown.ts inline
    static let imageRef = re("!\\[[^\\]]*\\]\\(([^)]+)\\)")
    static let linkRef = re("\\[([^\\]]*)\\]\\(([^)]+)\\)")
    struct Inline { var nodes: [JSONValue] = []; var media: [(String, MomentKind)] = [] }
    static func inline(_ s: String, _ marks: [JSONValue] = []) -> Inline {
        let u = Array(s.utf16); var out = Inline(); var buf: U = []
        func flush() {
            guard !buf.isEmpty else { return }
            var n: [String: JSONValue] = ["type": .string("text"), "text": .string(str(buf[...]))]
            if !marks.isEmpty { n["marks"] = .array(marks) }
            out.nodes.append(.object(n)); buf = []
        }
        func with(_ m: JSONValue) -> [JSONValue] { marks + [m] }
        func indexOf(_ needle: U, from: Int) -> Int {
            guard from <= u.count - needle.count else { return -1 }
            var i = max(from, 0)
            while i + needle.count <= u.count { if Array(u[i..<i + needle.count]) == needle { return i }; i += 1 }
            return -1
        }
        let bs: UInt16 = 0x5C, tick: UInt16 = 0x60, bang: UInt16 = 0x21, open: UInt16 = 0x5B, star: UInt16 = 0x2A, under: UInt16 = 0x5F, nl: UInt16 = 0x0A
        var i = 0
        while i < u.count {
            let c = u[i]
            if c == bs && i + 1 < u.count { buf.append(u[i + 1]); i += 2; continue }
            if c == tick {
                let j = indexOf([tick], from: i + 1)
                if j > i { flush(); out.nodes.append(.object(["type": .string("text"), "text": .string(str(u[(i + 1)..<j])), "marks": .array(with(.object(["type": .string("code")])))])); i = j + 1; continue }
            }
            if c == bang && i + 1 < u.count && u[i + 1] == open {
                let rest = str(u[i...])
                if let m = match(imageRef, rest), let whole = m[0] {
                    if let ref = parseMomentURL(m[1] ?? "") { flush(); out.media.append((ref.identifier, ref.kind)) }
                    i += whole.utf16.count; continue
                }
            }
            if c == open {
                let rest = str(u[i...])
                if let m = match(linkRef, rest), let whole = m[0] {
                    flush()
                    let inner: Inline
                    if let href = ChapterMarkdown.safeHref(.string(m[2] ?? "")) { inner = inline(m[1] ?? "", with(.object(["type": .string("link"), "attrs": .object(["href": .string(href)])]))) }
                    else { inner = inline(m[1] ?? "", marks) }
                    out.nodes += inner.nodes; out.media += inner.media
                    i += whole.utf16.count; continue
                }
            }
            if c == star || c == under {
                let dbl = Array(u[i..<min(i + 2, u.count)])
                if dbl == [star, star] || dbl == [under, under] {
                    let close = indexOf(dbl, from: i + 2)
                    if close > i + 1 { flush(); let inner = inline(str(u[(i + 2)..<close]), with(.object(["type": .string("bold")]))); out.nodes += inner.nodes; out.media += inner.media; i = close + 2; continue }
                } else {
                    let close = indexOf([c], from: i + 1)
                    if close > i + 1 { flush(); let inner = inline(str(u[(i + 1)..<close]), with(.object(["type": .string("italic")]))); out.nodes += inner.nodes; out.media += inner.media; i = close + 1; continue }
                }
            }
            if c == nl { flush(); out.nodes.append(.object(["type": .string("hardBreak")])); i += 1; continue }
            buf.append(c); i += 1
        }
        flush()
        return out
    }
    static func paragraph(_ text: String) -> [JSONValue] {
        let r = inline(trim(text)); var out: [JSONValue] = []
        if !r.nodes.isEmpty { out.append(.object(["type": .string("paragraph"), "content": .array(r.nodes)])) }
        for (id, kind) in r.media { out.append(.object(["type": .string(mediaRef), "attrs": .object(["identifier": .string(id), "kind": .string(kind.rawValue)])])) }
        return out
    }

    // MARK: markdown.ts blocks
    static let fence = re("```(\\S+)?\\s*\\z"), heading = re("(#{1,6})\\s+([^\\n\\r\\u2028\\u2029]*)\\z"), hr = re("(?:---+|\\*\\*\\*+|___+)\\s*\\z")
    static let bullet = re("[-*+]\\s+([^\\n\\r\\u2028\\u2029]*)\\z"), task = re("[-*+]\\s+\\[([ xX])\\]\\s+([^\\n\\r\\u2028\\u2029]*)\\z")
    static let ordered = re("\\d+[.)]\\s+([^\\n\\r\\u2028\\u2029]*)\\z"), quote = re(">\\s?([^\\n\\r\\u2028\\u2029]*)\\z")
    static func test(_ r: NSRegularExpression, _ s: String) -> Bool { match(r, s) != nil }

    public static func markdownToBlocks(_ md: String) -> [JSONValue] {
        // md.replace(/\r\n?/g, '\n').split('\n')
        var normalized = U(); let src = Array(md.utf16); var k = 0
        while k < src.count { if src[k] == 0x0D { normalized.append(0x0A); if k + 1 < src.count, src[k + 1] == 0x0A { k += 1 } } else { normalized.append(src[k]) }; k += 1 }
        let lines = normalized.split(separator: 0x0A, omittingEmptySubsequences: false).map { str($0) }
        var blocks: [JSONValue] = []; var i = 0
        while i < lines.count {
            let line = lines[i]
            if trim(line).isEmpty { i += 1; continue }
            if let f = match(fence, line) {
                var body: [String] = []; i += 1
                while i < lines.count && !test(fence, lines[i]) { body.append(lines[i]); i += 1 }
                i += 1
                blocks.append(.object(["type": .string("codeBlock"), "attrs": .object(["language": f[1].map(JSONValue.string) ?? .null]),
                                       "content": .array(body.isEmpty ? [] : [.object(["type": .string("text"), "text": .string(body.joined(separator: "\n"))])])]))
                continue
            }
            if let h = match(heading, line) {
                blocks.append(.object(["type": .string("heading"), "attrs": .object(["level": .number(Double(min(h[1]!.utf16.count, 3)))]), "content": .array(inline(trim(h[2] ?? "")).nodes)]))
                i += 1; continue
            }
            if test(hr, line) { blocks.append(.object(["type": .string("horizontalRule")])); i += 1; continue }
            if test(quote, line) {
                var inner: [String] = []
                while i < lines.count, let q = match(quote, lines[i]) { inner.append(q[1] ?? ""); i += 1 }
                blocks.append(.object(["type": .string("blockquote"), "content": .array(markdownToBlocks(inner.joined(separator: "\n")))]))
                continue
            }
            if test(task, line) {
                var items: [JSONValue] = []
                while i < lines.count, let m = match(task, lines[i]) {
                    items.append(.object(["type": .string("taskItem"), "attrs": .object(["checked": .bool(m[1]?.lowercased() == "x")]),
                                          "content": .array([.object(["type": .string("paragraph"), "content": .array(inline(trim(m[2] ?? "")).nodes)])])]))
                    i += 1
                }
                blocks.append(.object(["type": .string("taskList"), "content": .array(items)]))
                continue
            }
            if test(bullet, line) || test(ordered, line) {
                let isOrdered = test(ordered, line), r = isOrdered ? ordered : bullet
                var items: [JSONValue] = []
                while i < lines.count, !test(task, lines[i]), let m = match(r, lines[i]) {
                    items.append(.object(["type": .string("listItem"), "content": .array([.object(["type": .string("paragraph"), "content": .array(inline(trim(m[1] ?? "")).nodes)])])]))
                    i += 1
                }
                blocks.append(.object(["type": .string(isOrdered ? "orderedList" : "bulletList"), "content": .array(items)]))
                continue
            }
            var para: [String] = []
            while i < lines.count, !trim(lines[i]).isEmpty, !test(fence, lines[i]), !test(heading, lines[i]), !test(hr, lines[i]),
                  !test(quote, lines[i]), !test(bullet, lines[i]), !test(ordered, lines[i]) { para.append(lines[i]); i += 1 }
            blocks += paragraph(para.joined(separator: "\n"))
        }
        return blocks
    }

    // MARK: splitTitle
    static func plainText(_ n: JSONValue) -> String {
        if n["type"].string == "text" { return n["text"].string ?? "" }
        if n["type"].string == "hardBreak" { return " " }
        return n["content"].array.map(plainText).joined()
    }
    static func prefix140(_ s: String) -> String { str(Array(s.utf16).prefix(140)) }
    public static func splitTitle(_ blocks: [JSONValue]) -> (title: String, body: [JSONValue]) {
        guard let first = blocks.first else { return ("", blocks) }
        if first["type"].string == "heading" {
            let title = trim(plainText(first))
            return title.isEmpty ? ("", blocks) : (prefix140(title), Array(blocks.dropFirst()))
        }
        if first["type"].string == "paragraph" {
            let content = first["content"].array
            let brk = content.firstIndex { $0["type"].string == "hardBreak" }
            let head = brk.map { Array(content[..<$0]) } ?? content
            let title = trim(head.map(plainText).joined())
            if title.isEmpty { return ("", blocks) }
            if brk == nil && title.utf16.count > 140 { return ("", blocks) }
            let rest = brk.map { Array(content[($0 + 1)...]) } ?? []
            var body: [JSONValue] = rest.isEmpty ? [] : [.object(["type": .string("paragraph"), "content": .array(rest)])]
            body += blocks.dropFirst()
            return (prefix140(title), body)
        }
        return ("", blocks)
    }
}
