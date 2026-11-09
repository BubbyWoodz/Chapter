// SPDX-License-Identifier: AGPL-3.0-or-later
// Reminders on the original relay API (server/internal/api/reminders.go): GET/PUT /v1/reminders and
// DELETE /v1/reminders/{id}. Semantics are upstream's: a reminder is an id and a cleartext fire time
// (migrations/0001_init.sql, a documented accepted leak), one-shot (an upsert reschedules and clears
// `dispatched`; there is no recurrence anywhere upstream), and it "fires generic ('Reminder')"
// (CLAUDE.md §3; the scheduler calls it "a journal nudge"). So a notification carries the generic
// title only: no body, no journal content, nothing that reaches the lock screen. Ids are random
// 128-bit hex like the web's `src/sync/ids.ts`, never time-derived, because the relay sees them.
import Foundation

public enum ChapterReminders {
    public struct Reminder: Equatable, Sendable {
        public let id: String, fireAt: Date, dispatched: Bool
        public init(id: String, fireAt: Date, dispatched: Bool = false) { self.id = id; self.fireAt = fireAt; self.dispatched = dispatched }
    }
    /// One local notification to have pending: generic content, keyed by the reminder id.
    public struct Notification: Equatable, Sendable { public let identifier: String, fireAt: Date }
    public static let notificationPrefix = "chapter.reminder."
    public static let notificationTitle = "Reminder"
    /// Everything a reminder notification shows. Deliberately only the generic title.
    public struct Content: Equatable, Sendable { public let title: String, body: String }
    public static let content = Content(title: notificationTitle, body: "")
    /// A fresh reminder id: 16 random bytes as lowercase hex, like `randomId()` in src/sync/ids.ts.
    public static func newID() -> String { var g = SystemRandomNumberGenerator(); return newID(using: &g) }
    public static func newID<G: RandomNumberGenerator>(using g: inout G) -> String {
        var bytes: [UInt8] = []
        for _ in 0..<2 { withUnsafeBytes(of: g.next().littleEndian) { bytes.append(contentsOf: $0) } }
        return bytes.map { ($0 < 16 ? "0" : "") + String($0, radix: 16) }.joined()
    }
    /// iOS keeps at most 64 pending local notifications per app.
    public static let pendingLimit = 64

    /// The server's recordIDRe `^[A-Za-z0-9_.:-]{1,128}$`.
    public static func serverAcceptsID(_ id: String) -> Bool {
        let u = Array(id.utf8)
        return (1...128).contains(u.count) && u.allSatisfy { (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 0x5F || $0 == 0x2E || $0 == 0x3A || $0 == 0x2D }
    }
    /// What this client creates: the server rule minus "." and "..", which a DELETE path
    /// can't carry (URL dot-segment removal would address another route).
    public static func validID(_ id: String) -> Bool { serverAcceptsID(id) && id != "." && id != ".." }

    /// `fire_at` for PUT: UTC, whole seconds, the form GET returns (Go `Format(time.RFC3339)`).
    public static func format(_ date: Date) throws -> String {
        let t = date.timeIntervalSince1970
        guard t.isFinite else { throw ChapterError.unsupported }
        let seconds = Int64(t.rounded(.down))
        let days = seconds >= 0 ? seconds / 86400 : (seconds - 86399) / 86400
        let rem = Int(seconds - days * 86400)
        let (y, m, d) = civil(days)
        guard (0...9999).contains(y) else { throw ChapterError.unsupported }
        func p(_ v: Int, _ n: Int) -> String { let s = String(v); return String(repeating: "0", count: max(0, n - s.count)) + s }
        return "\(p(y, 4))-\(p(m, 2))-\(p(d, 2))T\(p(rem / 3600, 2)):\(p(rem / 60 % 60, 2)):\(p(rem % 60, 2))Z"
    }

    /// Go `time.Parse(time.RFC3339, s)` as the PUT handler applies it: seconds and nanoseconds.
    public static func parse(_ s: String) -> (seconds: Int64, nanos: Int)? {
        let u = Array(s.utf8); var i = 0
        func num(_ n: Int) -> Int? {
            guard i + n <= u.count else { return nil }
            var v = 0; for k in 0..<n { let c = u[i + k]; guard c >= 48, c <= 57 else { return nil }; v = v * 10 + Int(c - 48) }
            i += n; return v
        }
        func lit(_ c: UInt8) -> Bool { guard i < u.count, u[i] == c else { return false }; i += 1; return true }
        guard let year = num(4), lit(0x2D), let month = num(2), lit(0x2D), let day = num(2), lit(0x54),
              let hour = num(2), lit(0x3A), let minute = num(2), lit(0x3A), let second = num(2) else { return nil }
        guard (1...12).contains(month), day >= 1, day <= daysIn(month, year), hour <= 23, minute <= 59, second <= 59 else { return nil }
        var nanos = 0
        if i < u.count, u[i] == 0x2E || u[i] == 0x2C {
            i += 1; var n = 0
            while i < u.count, u[i] >= 48, u[i] <= 57 { if n < 9 { nanos = nanos * 10 + Int(u[i] - 48) }; n += 1; i += 1 }
            guard n > 0 else { return nil }
            for _ in n..<max(n, 9) { nanos *= 10 }
        }
        var offset = 0
        if lit(0x5A) {}
        else if i < u.count, u[i] == 0x2B || u[i] == 0x2D {
            let sign = u[i] == 0x2D ? -1 : 1; i += 1
            guard let oh = num(2), lit(0x3A), let om = num(2), oh <= 24, om <= 60 else { return nil }
            offset = sign * (oh * 3600 + om * 60)
        } else { return nil }
        guard i == u.count else { return nil }
        let seconds = daysFromCivil(year, month, day) * 86400 + Int64(hour * 3600 + minute * 60 + second) - Int64(offset)
        return (seconds, nanos)
    }
    static func leap(_ y: Int) -> Bool { y % 4 == 0 && (y % 100 != 0 || y % 400 == 0) }
    static func daysIn(_ m: Int, _ y: Int) -> Int { [31, leap(y) ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][m - 1] }
    /// Proleptic Gregorian (Foundation's Gregorian calendar switches to Julian before 1582).
    static func daysFromCivil(_ y0: Int, _ m: Int, _ d: Int) -> Int64 {
        let y = m <= 2 ? y0 - 1 : y0
        let era = (y >= 0 ? y : y - 399) / 400, yoe = y - era * 400
        let doy = (153 * (m + (m > 2 ? -3 : 9)) + 2) / 5 + d - 1
        return Int64(era * 146097 + yoe * 365 + yoe / 4 - yoe / 100 + doy - 719468)
    }
    static func civil(_ z0: Int64) -> (Int, Int, Int) {
        let z = z0 + 719468
        let era = (z >= 0 ? z : z - 146096) / 146097
        let doe = z - era * 146097
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1, m = mp < 10 ? mp + 3 : mp - 9
        return (Int(yoe + era * 400 + (m <= 2 ? 1 : 0)), Int(m), Int(d))
    }

    /// The local notifications to have pending: every reminder still in the future, soonest first
    /// (ties by id), within the platform limit. `dispatched` is ignored: the server scheduler only
    /// logs, so it delivers nothing, and an upsert always clears it.
    public static func plan(_ reminders: [Reminder], now: Date, limit: Int = pendingLimit) -> [Notification] {
        let future = reminders.filter { $0.fireAt > now && serverAcceptsID($0.id) }
        var seen = Set<String>(), unique: [Reminder] = []
        for r in future.sorted(by: { $0.fireAt != $1.fireAt ? $0.fireAt < $1.fireAt : Array($0.id.utf8).lexicographicallyPrecedes(Array($1.id.utf8)) }) where seen.insert(r.id).inserted { unique.append(r) }
        return unique.prefix(max(0, limit)).map { Notification(identifier: notificationPrefix + $0.id, fireAt: $0.fireAt) }
    }
    /// What to change in the pending set. Only this client's identifiers are touched; one whose
    /// time changed is re-added (adding with an existing identifier replaces it).
    public static func reconcile(pending: [Notification], plan: [Notification]) -> (add: [Notification], remove: [String]) {
        let ours = pending.filter { $0.identifier.hasPrefix(notificationPrefix) }
        let wanted = Dictionary(plan.map { ($0.identifier, $0.fireAt) }, uniquingKeysWith: { a, _ in a })
        let have = Dictionary(ours.map { ($0.identifier, $0.fireAt) }, uniquingKeysWith: { a, _ in a })
        let remove = ours.map(\.identifier).filter { wanted[$0] == nil }
        let add = plan.filter { have[$0.identifier] != $0.fireAt }
        var seen = Set<String>()
        return (add, remove.filter { seen.insert($0).inserted })
    }
}

extension Relay {
    struct ReminderItem: Decodable { let reminder_id: String; let fire_at: String; let dispatched: Bool }
    struct ReminderList: Decodable { let reminders: [ReminderItem] }
    /// GET /v1/reminders, ordered by fire time like the server.
    public func reminders(token: String) async throws -> [ChapterReminders.Reminder] {
        let data = try await send("v1/reminders", method: "GET", token: token, maxBytes: 4 << 20)
        let list = try JSONDecoder().decode(ReminderList.self, from: data)
        return try list.reminders.map { item in
            guard ChapterReminders.serverAcceptsID(item.reminder_id), let t = ChapterReminders.parse(item.fire_at) else { throw ChapterError.corruptData }
            return ChapterReminders.Reminder(id: item.reminder_id, fireAt: Date(timeIntervalSince1970: TimeInterval(t.seconds) + TimeInterval(t.nanos) / 1e9), dispatched: item.dispatched)
        }
    }
    /// PUT /v1/reminders: create or reschedule (clears `dispatched` on the server).
    public func putReminder(id: String, fireAt: Date, token: String) async throws {
        guard ChapterReminders.validID(id) else { throw ChapterError.unsupported }
        let body = try JSONEncoder().encode(["reminder_id": id, "fire_at": try ChapterReminders.format(fireAt)])
        let data = try await send("v1/reminders", method: "PUT", body: body, token: token, maxBytes: 4096, expectedStatus: 200)
        guard (try? JSONDecoder().decode([String: String].self, from: data))?["reminder_id"] == id else { throw ChapterError.corruptData }
    }
    /// DELETE /v1/reminders/{id}: exactly 204; a missing reminder is HTTP 404.
    public func deleteReminder(id: String, token: String) async throws {
        guard ChapterReminders.validID(id) else { throw ChapterError.unsupported }
        _ = try await send("v1/reminders/\(id)", method: "DELETE", token: token, maxBytes: 0, expectedStatus: 204)
    }
}
