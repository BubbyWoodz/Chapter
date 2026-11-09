// SPDX-License-Identifier: AGPL-3.0-or-later
// Port of the web importer's run step (apps/client/src/import/run.ts importDayOne): Day One
// journals are matched to notebooks by name (case-insensitively, else created with the web's
// colours and covers), each entry is created, its media attached, consecutive images grouped
// into a gallery, and the final document, labels and original date written back. The app
// supplies the writes through DayOneImportTarget, so everything goes through the normal
// encrypted, queued paths. Like the web, a malformed record stops the import where it is.
import Foundation

/// Every write is async, so `run` stays off the main actor (inflating media there would stall
/// the UI) while an app adapter forwards each call to its main-actor model.
public protocol DayOneImportTarget: AnyObject {
    /// Existing notebooks, in the app's order, read once when the import starts.
    var importJournals: [(id: String, name: String)] { get }
    func importNewJournal(id: String, name: String, subtitle: String, color: String, cover: String) async throws
    func importCreateEntry(journalID: String, title: String?, labels: [String]) async throws -> String
    /// Encrypt and queue one file; returns the attachment's node attrs, or nil when it can't be attached.
    func importAddMedia(entryID: String, _ moment: DayOneArchive.Resolved) async throws -> JSValue?
    /// `createdAt` is epoch milliseconds; a nil title keeps the date-based default.
    func importUpdateEntry(id: String, title: String?, bodyJSON: String, bodyText: String, labels: [String], createdAt: Double) async throws
}

public enum ChapterDayOneImport {
    public struct Summary: Equatable, Sendable { public var journals = 0, entries = 0, media = 0, skippedMedia = 0 }
    public struct Progress: Equatable, Sendable {
        public let done: Int, total: Int, current: String
        public init(done: Int, total: Int, current: String) { self.done = done; self.total = total; self.current = current }
    }
    public static let colors = ["#B0563A", "#4E8B85", "#6A6AA0", "#B08A2E", "#5A7BA6", "#6E8B5E", "#8E6A93", "#C06A4A"]
    public static let covers = ["lines", "dots", "grid", "plain"]
    public static let subtitle = "Imported from Day One"

    public static func run(
        _ archive: DayOneArchive, into target: DayOneImportTarget, timeZone: TimeZone = .current,
        now: () -> Double = { (Date().timeIntervalSince1970 * 1000).rounded(.down) },
        random: () -> Double = { Double.random(in: 0..<1) },
        progress: @Sendable (Progress) -> Void = { _ in }
    ) async throws -> Summary {
        var summary = Summary()
        let total = archive.entryCount
        var done = 0, created = 0
        var byName: [[UInt16]: String] = [:]
        for j in target.importJournals { byName[Array(jsLowercase(j.name).utf16)] = j.id }
        func journalID(_ name: String) async throws -> String {
            let key = Array(jsLowercase(name).utf16)
            if let existing = byName[key], !existing.isEmpty { return existing }
            let id = "j-import-\(created)-\(base36(now()))\(base36((random() * 1e6).rounded(.down)))"
            try await target.importNewJournal(id: id, name: name, subtitle: subtitle, color: colors[created % colors.count], cover: covers[created % covers.count])
            byName[key] = id; created += 1; summary.journals += 1
            return id
        }
        for journal in archive.journals {
            let jid = try await journalID(journal.name)
            for entry in journal.entries {
                let text: String
                switch try DayOneArchive.prop(entry, "text") {
                case nil, .null?: text = ""
                case .string(let s)?: text = s
                default: throw DayOneArchive.ImportError.malformed // md.replace is not a function
                }
                let (title, body) = ChapterDayOne.splitTitle(ChapterDayOne.markdownToBlocks(text))
                var labels: [String] = []
                switch entry.get("tags") {
                case nil, .null?: break
                case .array(let tags)?: for case .string(let t) in tags { let v = ChapterDayOne.trim(t); if !v.isEmpty { labels.append(v) } }
                default: throw DayOneArchive.ImportError.malformed // tags.filter is not a function
                }
                let entryID = try await target.importCreateEntry(journalID: jid, title: title.isEmpty ? nil : title, labels: labels)
                let content = try await resolveMedia(body, entry, archive, target, entryID, &summary)
                let doc = JSValue.object([("type", .string("doc")), ("content", .array(content.isEmpty ? [.object([("type", .string("paragraph"))])] : content))])
                let json = doc.stringify()
                let bodyText = try RichDocument(json: json).plainText
                try await target.importUpdateEntry(id: entryID, title: title.isEmpty ? nil : title, bodyJSON: json, bodyText: bodyText, labels: labels,
                                             createdAt: parseDate(entry.get("creationDate"), timeZone: timeZone, now: now))
                summary.entries += 1; done += 1
                progress(Progress(done: done, total: total, current: title.isEmpty ? "Untitled entry" : title))
            }
        }
        return summary
    }

    static func resolveMedia(_ body: [JSONValue], _ entry: JSValue, _ archive: DayOneArchive, _ target: DayOneImportTarget, _ entryID: String, _ summary: inout Summary) async throws -> [JSValue] {
        let moments = try DayOneArchive.entryMoments(entry)
        var out: [JSValue] = [], run: [JSValue] = []
        func flush() {
            if run.count == 1 { out.append(.object([("type", .string("mediaAttachment")), ("attrs", run[0])])) }
            else if run.count > 1 { out.append(.object([("type", .string("mediaGallery")), ("attrs", .object([("images", .array(run))]))])) }
            run = []
        }
        for node in body {
            guard node["type"].string == ChapterDayOne.mediaRef else { flush(); out.append(JSValue(node)); continue }
            let identifier = node["attrs"]["identifier"].string ?? ""
            guard let found = moments[Array(identifier.utf16)], let resolved = try archive.resolve(found.moment, found.kind) else { summary.skippedMedia += 1; continue }
            guard let att = try await target.importAddMedia(entryID: entryID, resolved) else { summary.skippedMedia += 1; continue }
            summary.media += 1
            if att.get("kind") == .string("image") { run.append(att) } else { flush(); out.append(.object([("type", .string("mediaAttachment")), ("attrs", att)])) }
        }
        flush()
        return out
    }

    /// `Number.prototype.toString(36)` for the non-negative integers the web id stamp uses.
    static func base36(_ x: Double) -> String {
        guard x >= 1 else { return "0" }
        var n = x, digits: [Character] = []
        let alphabet = Array("0123456789abcdefghijklmnopqrstuvwxyz")
        while n >= 1 { let d = n.truncatingRemainder(dividingBy: 36); digits.append(alphabet[Int(d)]); n = ((n - d) / 36).rounded(.down) }
        return String(digits.reversed())
    }

    /// `String.prototype.toLowerCase`, including the Final_Sigma rule Swift's `lowercased()` skips.
    public static func jsLowercase(_ s: String) -> String {
        let scalars = Array(s.unicodeScalars)
        var out = String.UnicodeScalarView()
        func cased(_ c: Unicode.Scalar) -> Bool { c.properties.isCased }
        func ignorable(_ c: Unicode.Scalar) -> Bool { c.properties.isCaseIgnorable }
        for (i, c) in scalars.enumerated() {
            if c == "\u{03A3}" {
                var before = false, after = false
                var k = i - 1; while k >= 0, ignorable(scalars[k]) { k -= 1 }; if k >= 0, cased(scalars[k]) { before = true }
                k = i + 1; while k < scalars.count, ignorable(scalars[k]) { k += 1 }; if k < scalars.count, cased(scalars[k]) { after = true }
                out.append(before && !after ? "\u{03C2}" : "\u{03C3}")
            } else { out.append(contentsOf: c.properties.lowercaseMapping.unicodeScalars) }
        }
        return String(out)
    }

    /// run.ts parseDate: the ECMAScript date-time string format as V8 reads it; anything else
    /// (V8's legacy formats too) falls back to now. Date-only forms are UTC, date-times without
    /// an offset are local time.
    static func parseDate(_ v: JSValue?, timeZone: TimeZone, now: () -> Double) -> Double {
        guard JSValue.truthy(v), let v else { return now() }
        return isoDate(DayOneArchive.template(v), timeZone: timeZone) ?? now()
    }
    static func isoDate(_ s: String, timeZone: TimeZone) -> Double? {
        let u = Array(s.utf8); var i = 0
        func digits(_ n: Int) -> Int? {
            guard i + n <= u.count else { return nil }
            var v = 0; for k in 0..<n { let c = u[i + k]; guard c >= 48, c <= 57 else { return nil }; v = v * 10 + Int(c - 48) }
            i += n; return v
        }
        func eat(_ c: UInt8) -> Bool { if i < u.count, u[i] == c { i += 1; return true }; return false }
        var year: Int
        if i < u.count, u[i] == 0x2B || u[i] == 0x2D {
            let negative = u[i] == 0x2D; i += 1
            guard let y = digits(6), !(negative && y == 0) else { return nil }; year = negative ? -y : y
        } else { guard let y = digits(4) else { return nil }; year = y }
        var month = 1, day = 1
        if eat(0x2D) { guard let m = digits(2), (1...12).contains(m) else { return nil }; month = m
            if eat(0x2D) { guard let d = digits(2), (1...31).contains(d) else { return nil }; day = d } }
        var h = 0, mi = 0, sec = 0, ms = 0, offset: Int?, hasTime = false
        if i < u.count, u[i] == 0x54 || u[i] == 0x74 || u[i] == 0x20 {
            i += 1; hasTime = true
            guard let hh = digits(2), eat(0x3A), let mm = digits(2), mm <= 59 else { return nil }; h = hh; mi = mm
            if eat(0x3A) {
                guard let ss = digits(2), ss <= 59 else { return nil }; sec = ss
                if eat(0x2E) {
                    var n = 0, frac = 0
                    while i < u.count, u[i] >= 48, u[i] <= 57 { if n < 3 { frac = frac * 10 + Int(u[i] - 48) }; n += 1; i += 1 }
                    guard n > 0 else { return nil }; for _ in n..<max(n, 3) { frac *= 10 }; ms = frac
                }
            }
            guard h < 24 || (h == 24 && mi == 0 && sec == 0 && ms == 0) else { return nil }
            if eat(0x5A) || eat(0x7A) { offset = 0 }
            else if i < u.count, u[i] == 0x2B || u[i] == 0x2D {
                let sign = u[i] == 0x2D ? -1 : 1; i += 1
                guard let oh = digits(2), oh <= 23 else { return nil }
                _ = eat(0x3A); guard let om = digits(2), om <= 59 else { return nil }
                offset = sign * (oh * 60 + om)
            }
        }
        guard i == u.count else { return nil }
        let days = daysFromCivil(year, month, 1) + Double(day - 1)
        let local = days * 86_400_000 + Double(h * 3_600_000 + mi * 60_000 + sec * 1000 + ms)
        let t: Double
        if let offset { t = local - Double(offset) * 60_000 }
        else if !hasTime { t = local }
        else { t = localToUTC(local, timeZone) }
        return abs(t) <= 8.64e15 ? t : nil
    }
    static func daysFromCivil(_ y0: Int, _ m: Int, _ d: Int) -> Double {
        let y = m <= 2 ? y0 - 1 : y0
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let doy = (153 * (m + (m > 2 ? -3 : 9)) + 2) / 5 + d - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return Double(era * 146097 + doe - 719468)
    }
    /// ECMAScript UTC(t): the earliest instant for repeated wall times, the offset from before
    /// the transition for skipped ones.
    static func localToUTC(_ local: Double, _ tz: TimeZone) -> Double {
        func offset(_ ms: Double) -> Double { Double(tz.secondsFromGMT(for: Date(timeIntervalSince1970: ms / 1000))) * 1000 }
        let before = offset(local - 86_400_000), after = offset(local + 86_400_000)
        let valid = Set([before, after]).map { local - $0 }.filter { offset($0) == local - $0 }
        return valid.min() ?? local - before
    }
}

extension VaultSnapshot {
    /// One imported entry, shaped like the web's createEntry + updateEntry result: the entry's
    /// own fields only (no native plain-text marker, since the body is a rich web document).
    public static func importedEntry(id: String, clock: Int64, journalID: String, title: String?, bodyJSON: String, bodyText: String,
                                     labels: [String], createdAt: Double, timeZone: TimeZone = .current) throws -> VaultRecord {
        try ProtocolNumbers.validate(clock)
        guard !id.isEmpty, !journalID.isEmpty, createdAt.isFinite else { throw ChapterError.unsupported }
        _ = try RichDocument(json: bodyJSON)
        let body: [String: JSONValue] = [
            "journalId": .string(journalID), "title": .string(title ?? EntryTemplates.defaultTitle(milliseconds: Double(clock), timeZone: timeZone)),
            "bodyText": .string(bodyText), "bodyJson": .string(bodyJSON), "labels": .array(labels.map { .string($0) }),
            "createdAt": .number(createdAt), "updatedAt": .number(Double(clock)),
        ]
        return VaultRecord(id: id, clock: clock, body: body, dirty: true)
    }
    /// Publishes an imported entry and its staged media in one write. Every staged upload must be
    /// referenced by the document, so the outbox never holds a file no entry points to.
    public mutating func addImportedEntry(_ record: VaultRecord, uploads: [MediaUpload]) throws {
        guard record.kind == "entry", !record.deleted, !records.contains(where: { $0.id == record.id }),
              records.contains(where: { $0.kind == "journal" && !$0.deleted && $0.journalID == record.journalID }) else { throw ChapterError.conflict }
        let referenced = Set(record.mediaReferences.map(\.id))
        var ids = Set((mediaUploads ?? []).map(\.id))
        for upload in uploads {
            try upload.validate()
            guard referenced.contains(upload.id), ids.insert(upload.id).inserted else { throw ChapterError.conflict }
        }
        records.append(record)
        if !uploads.isEmpty { mediaUploads = (mediaUploads ?? []) + uploads }
    }
}

extension JSValue {
    /// A JSONValue (keys sorted, so output is stable) as a JSValue.
    init(_ v: JSONValue) {
        switch v {
        case .object(let o): self = .object(o.keys.sorted().map { ($0, JSValue(o[$0]!)) })
        case .array(let a): self = .array(a.map(JSValue.init))
        case .string(let s): self = .string(s)
        case .number(let n): self = .number(n)
        case .bool(let b): self = .bool(b)
        case .null: self = .null
        }
    }
}
