// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

/// Port of the web's search/core.ts plus the Search sheet's searchHits: every token
/// must land on the title, labels, the entry date (several spellings, local time,
/// English and the active language's month names) or the body. Matching is on
/// UTF-16 code units after JavaScript toLowerCase(), exactly like the web.
public enum ChapterSearch {
    public struct Entry: Equatable {
        public let id: String, title: String, labels: [String], bodyText: String
        public let createdAt: Double, updatedAt: Double, deleted: Bool
        public init(id: String, title: String, labels: [String], bodyText: String, createdAt: Double, updatedAt: Double, deleted: Bool = false) {
            self.id = id; self.title = title; self.labels = labels; self.bodyText = bodyText
            self.createdAt = createdAt; self.updatedAt = updatedAt; self.deleted = deleted
        }
    }
    public enum Field: String, Equatable { case title, label, date, content }
    public struct Hit: Equatable { public let id: String; public let field: Field; public let snippet: String? }
    public struct MonthNames: Decodable, Equatable { public let long: [String]; public let short: [String] }

    static let maxResults = 50, snippetRadius = 60
    static let english = ["january", "february", "march", "april", "may", "june", "july", "august", "september", "october", "november", "december"]
    public static let monthNames: [String: MonthNames] = {
        guard let url = Bundle.module.url(forResource: "search-months", withExtension: "json"), let data = try? Data(contentsOf: url),
              let names = try? JSONDecoder().decode([String: MonthNames].self, from: data) else { return [:] }
        return names
    }()

    public static func entries(_ records: [VaultRecord]) -> [Entry] {
        records.map { r in
            let labels: [String] = r.body["labels"]?.array.compactMap { $0.string } ?? []
            let created = r.body["createdAt"]?.number ?? Double(r.clock)
            return Entry(id: r.id, title: r.body["title"]?.string ?? "", labels: labels, bodyText: r.body["bodyText"]?.string ?? "",
                         createdAt: created, updatedAt: r.body["updatedAt"]?.number ?? created, deleted: r.deleted)
        }
    }

    // MARK: JavaScript string semantics
    static func isWhitespace(_ u: UInt16) -> Bool { Unicode.Scalar(u).map { EntryLinkAuthoring.ecmaWhitespace.contains($0) } ?? false }
    /// String.prototype.toLowerCase(): full lowercase mappings, with the Final_Sigma context for U+03A3.
    public static func jsLower(_ s: String) -> String {
        let scalars = Array(s.unicodeScalars)
        var out = String.UnicodeScalarView()
        for (i, c) in scalars.enumerated() {
            if c.value == 0x03A3 {
                var j = i - 1; while j >= 0 && scalars[j].properties.isCaseIgnorable { j -= 1 }
                let before = j >= 0 && scalars[j].properties.isCased
                var k = i + 1; while k < scalars.count && scalars[k].properties.isCaseIgnorable { k += 1 }
                let after = k < scalars.count && scalars[k].properties.isCased
                out.append(Unicode.Scalar(before && !after ? 0x03C2 : 0x03C3)!)
            } else { out.append(contentsOf: c.properties.lowercaseMapping.unicodeScalars) }
        }
        return String(out)
    }
    static func trimmed(_ u: [UInt16]) -> ArraySlice<UInt16> {
        var a = 0, b = u.count
        while a < b && isWhitespace(u[a]) { a += 1 }
        while b > a && isWhitespace(u[b - 1]) { b -= 1 }
        return u[a..<b]
    }
    /// `s.replace(/\s+/g, ' ')`
    static func collapse<C: Collection>(_ u: C) -> [UInt16] where C.Element == UInt16 {
        var out: [UInt16] = []; var inSpace = false
        for c in u { if isWhitespace(c) { if !inSpace { out.append(32); inSpace = true } } else { out.append(c); inSpace = false } }
        return out
    }
    static func indexOf(_ hay: [UInt16], _ needle: [UInt16]) -> Int? {
        if needle.isEmpty { return 0 }
        guard hay.count >= needle.count else { return nil }
        var i = 0
        while i <= hay.count - needle.count {
            if hay[i] == needle[0] && hay[i..<(i + needle.count)].elementsEqual(needle) { return i }
            i += 1
        }
        return nil
    }
    static func includes(_ hay: [UInt16], _ needle: [UInt16]) -> Bool { indexOf(hay, needle) != nil }
    static func u16(_ s: String) -> [UInt16] { Array(s.utf16) }
    static func str<C: Collection>(_ u: C) -> String where C.Element == UInt16 { String(decoding: Array(u), as: UTF16.self) }

    /// search/core `normalize`: trim, toLowerCase, collapse whitespace.
    public static func normalize(_ raw: String) -> String { str(collapse(u16(jsLower(str(trimmed(u16(raw))))))) }

    static func dateHaystack(_ ts: Double, timeZone: TimeZone, months: MonthNames?) -> [UInt16] {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = timeZone
        let parts = cal.dateComponents([.year, .month, .day], from: Date(timeIntervalSince1970: ts / 1000))
        let y = parts.year ?? 1970, m = (parts.month ?? 1) - 1, d = parts.day ?? 1
        func pad(_ n: Int) -> String { n < 10 ? "0\(n)" : "\(n)" }
        let mon = english[m], mon3 = str(u16(mon).prefix(3))
        var spellings: [String] = []
        func add(_ s: String) { if !spellings.contains(s) { spellings.append(s) } }
        add("\(mon) \(d) \(y)"); add("\(d) \(mon) \(y)"); add("\(mon3) \(d) \(y)"); add("\(d) \(mon3) \(y)")
        add("\(y)-\(pad(m + 1))-\(pad(d))"); add("\(pad(d)).\(pad(m + 1)).\(y)"); add("\(d).\(m + 1).\(y)"); add("\(pad(m + 1))/\(pad(d))/\(y)")
        for name in [months?.long[m] ?? english[m].capitalized, months?.short[m] ?? str(u16(english[m].capitalized).prefix(3))] {
            let lower = jsLower(name)
            add("\(lower) \(d) \(y)"); add("\(d) \(lower) \(y)"); add("\(d). \(lower) \(y)")
        }
        return u16(spellings.joined(separator: " · "))
    }

    static func snippet(_ body: String, tokens: [[UInt16]]) -> String? {
        let lower = u16(jsLower(body)), text = u16(body)
        var at: Int?
        for t in tokens { if let i = indexOf(lower, t), at == nil || i < at! { at = i } }
        guard let at else { return nil }
        let start = max(0, at - snippetRadius), end = min(text.count, at + snippetRadius * 2)
        let core = str(trimmed(collapse(text[min(start, text.count)..<max(end, min(start, text.count))])))
        return (start > 0 ? "…" : "") + core + (end < text.count ? "…" : "")
    }

    /// search/core `search`.
    public static func search(_ entries: [Entry], query: String, timeZone: TimeZone, months: MonthNames?) -> [Hit] {
        let q = u16(normalize(query))
        let tokens = q.split(separator: 32, omittingEmptySubsequences: true).map(Array.init)
        if tokens.isEmpty { return [] }
        var hits: [(Hit, Double, Int)] = []
        let sep = u16(" · ")
        for e in entries where !e.deleted {
            let title = u16(jsLower(e.title)), label = u16(jsLower(e.labels.joined(separator: " · ")))
            let date = dateHaystack(e.createdAt, timeZone: timeZone, months: months), content = u16(jsLower(e.bodyText))
            let everything = title + sep + label + sep + date + sep + content
            guard tokens.allSatisfy({ includes(everything, $0) }) else { continue }
            let fields: [(Field, [UInt16])] = [(.title, title), (.label, label), (.date, date), (.content, content)]
            let field = fields.first(where: { includes($0.1, q) })?.0 ?? fields.first(where: { f in tokens.contains { includes(f.1, $0) } })?.0 ?? .content
            hits.append((Hit(id: e.id, field: field, snippet: snippet(e.bodyText, tokens: tokens)), e.updatedAt, hits.count))
        }
        let rank: [Field: Int] = [.title: 0, .label: 1, .date: 2, .content: 3]
        // Array.prototype.sort is stable: ties keep their input order.
        hits.sort { a, b in
            let ra = rank[a.0.field]!, rb = rank[b.0.field]!
            if ra != rb { return ra < rb }
            if a.1 != b.1 { return a.1 > b.1 }
            return a.2 < b.2
        }
        return hits.prefix(maxResults).map { $0.0 }
    }

    /// Search sheet `toEnglishMonths`: month words in the active language (long or
    /// short, or English) become English long names; nil when nothing changed.
    public static func toEnglishMonths(_ q: String, months: MonthNames?) -> String? {
        func stripDot(_ s: String) -> String { s.hasSuffix(".") ? String(s.dropLast()) : s }
        let out = q.split(separator: " ", omittingEmptySubsequences: false).map { sub -> String in
            let tok = String(sub), c = stripDot(tok)
            if c.utf16.count < 3 { return tok }
            for i in 0..<12 {
                let forms = [months?.long[i] ?? english[i], months?.short[i] ?? english[i], english[i]].map { stripDot(jsLower($0)) }
                if forms.contains(where: { $0 == c || u16($0).starts(with: u16(c)) }) { return english[i] }
            }
            return tok
        }
        let joined = out.joined(separator: " ")
        return joined == q ? nil : joined
    }

    /// Search sheet `searchHits`: the typed query unioned with its month-translated
    /// form; an empty query lists the 8 most recently touched entries.
    public static func searchHits(_ entries: [Entry], query: String, locale: String, timeZone: TimeZone = .current) -> [Hit] {
        let months = monthNames[locale] ?? monthNames["en"]
        let normalized = normalize(query)
        if !normalized.isEmpty {
            let base = search(entries, query: query, timeZone: timeZone, months: months)
            guard let alt = toEnglishMonths(normalized, months: months) else { return base }
            let seen = Set(base.map(\.id))
            return base + search(entries, query: alt, timeZone: timeZone, months: months).filter { !seen.contains($0.id) }
        }
        return entries.enumerated().sorted { a, b in a.element.updatedAt != b.element.updatedAt ? a.element.updatedAt > b.element.updatedAt : a.offset < b.offset }
            .prefix(8).map { Hit(id: $0.element.id, field: .content, snippet: nil) }
    }
}
