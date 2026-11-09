// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

/// Port of the web's state/stats.ts: pure stats over live entries, UTC day boundaries
/// (the calendar grid's), JavaScript trim()/split(/\s+/) word counting.
public enum ChapterStats {
    static let dayMS = 86_400_000.0
    public struct Item: Equatable { public let id: String; public let createdAt: Double; public let bodyText: String
        public init(id: String, createdAt: Double, bodyText: String) { self.id = id; self.createdAt = createdAt; self.bodyText = bodyText } }
    public static func items(_ records: [VaultRecord]) -> [Item] {
        records.map { Item(id: $0.id, createdAt: $0.body["createdAt"]?.number ?? Double($0.clock), bodyText: $0.body["bodyText"]?.string ?? "") }
    }
    public static func utcDayIndex(_ ts: Double) -> Int { Int((ts / dayMS).rounded(.down)) }

    /// Consecutive UTC days ending today, or yesterday as grace.
    public static func dayStreak(_ entries: [Item], now: Double) -> Int {
        let days = Set(entries.map { utcDayIndex($0.createdAt) })
        var d = utcDayIndex(now); if !days.contains(d) { d -= 1 }
        var streak = 0; while days.contains(d) { streak += 1; d -= 1 }
        return streak
    }
    /// JavaScript `text.trim()` then `split(/\s+/).length` (ECMAScript whitespace and line terminators).
    public static func wordCount(_ text: String) -> Int {
        let ws = EntryLinkAuthoring.ecmaWhitespace
        var count = 0, inWord = false
        for scalar in text.unicodeScalars {
            if ws.contains(scalar) { inWord = false } else if !inWord { inWord = true; count += 1 }
        }
        return count
    }
    public static func totalWords(_ entries: [Item]) -> Int { entries.reduce(0) { $0 + wordCount($1.bodyText) } }
    public static func journaledDays(_ entries: [Item]) -> Int { Set(entries.map { utcDayIndex($0.createdAt) }).count }
    public static func longestStreak(_ entries: [Item]) -> Int {
        var best = 0, run = 0, prev: Int?
        for d in Set(entries.map { utcDayIndex($0.createdAt) }).sorted() {
            run = prev.map { d == $0 + 1 } == true ? run + 1 : 1
            best = max(best, run); prev = d
        }
        return best
    }
    static func utcParts(_ ts: Double) -> DateComponents {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.dateComponents([.year, .month, .day, .weekday], from: Date(timeIntervalSince1970: ts / 1000))
    }
    /// Words in entries of the UTC (year, month 0–11).
    public static func monthWords(_ entries: [Item], year: Int, month: Int) -> Int {
        entries.filter { let p = utcParts($0.createdAt); return p.year == year && (p.month ?? 0) - 1 == month }.reduce(0) { $0 + wordCount($1.bodyText) }
    }
    /// 999 → "999", 1438 → "1.4k", 2000 → "2k" (JavaScript toFixed(1), then drop ".0").
    public static func compactCount(_ n: Int) -> String {
        guard n >= 1000 else { return String(n) }
        let tenths = jsToFixed1(Double(n) / 1000)
        return (tenths.hasSuffix(".0") ? String(tenths.dropLast(2)) : tenths) + "k"
    }
    /// Number.prototype.toFixed(1) for non-negative values: the double's exact decimal
    /// expansion (printf prints it exactly), rounded half up as the spec picks the larger n.
    static func jsToFixed1(_ x: Double) -> String {
        let exact = String(format: "%.80f", x)
        let parts = exact.split(separator: ".", maxSplits: 1)
        var integer = Array(String(parts[0])).compactMap { $0.wholeNumberValue }
        let fraction = Array(String(parts.count > 1 ? parts[1] : "0")).compactMap { $0.wholeNumberValue }
        var tenth = fraction.first ?? 0
        let rest = Array(fraction.dropFirst())
        if let first = rest.first, first >= 5 { // >= half: the tie (5 followed by zeros) rounds up too
            tenth += 1
            if tenth == 10 {
                tenth = 0
                var i = integer.count - 1
                while i >= 0 { integer[i] += 1; if integer[i] < 10 { break }; integer[i] = 0; i -= 1 }
                if i < 0 { integer.insert(1, at: 0) }
            }
        }
        return integer.map(String.init).joined() + "." + String(tenth)
    }
    /// Entries on the UTC month (0–11)/day from years before `year`, newest first.
    public static func onThisDay(_ entries: [Item], month: Int, day: Int, year: Int) -> [Item] {
        entries.filter { let p = utcParts($0.createdAt); return (p.month ?? 0) - 1 == month && p.day == day && (p.year ?? 0) < year }
            .sorted { $0.createdAt > $1.createdAt }
    }
    /// Per-day counts for the trailing `weeks` Monday-first UTC weeks, oldest first.
    public static func dailyCounts(_ entries: [Item], now: Double, weeks: Int) -> [Int] {
        let today = utcDayIndex(now)
        let monFirst = ((utcParts(now).weekday ?? 1) - 1 + 6) % 7 // weekday 1 = Sunday, like getUTCDay()+1
        let end = today - monFirst + 6, start = end - weeks * 7 + 1
        var counts = [Int](repeating: 0, count: weeks * 7)
        for e in entries { let i = utcDayIndex(e.createdAt) - start; if i >= 0 && i < counts.count { counts[i] += 1 } }
        return counts
    }
}
