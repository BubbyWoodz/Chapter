// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

/// Port of the web export/journal.ts + export/collect.ts: one notebook as the public
/// `mneme-journal-export` v1 archive (manifest, one JSON file per entry, decrypted
/// media, README). Everything happens on the device; the archive is plaintext.
public enum ChapterExport {
    public struct Journal: Sendable { public let id, name, subtitle, color, cover: String; public let createdAt, updatedAt: Double?
        public init(id: String, name: String, subtitle: String, color: String, cover: String, createdAt: Double?, updatedAt: Double?) {
            self.id = id; self.name = name; self.subtitle = subtitle; self.color = color; self.cover = cover; self.createdAt = createdAt; self.updatedAt = updatedAt } }
    public struct Entry: Sendable { public let id, journalId, title, bodyText: String; public let bodyJson: String?; public let labels: [String]; public let createdAt, updatedAt: Double; public let attachments: [JSONValue]; public let deleted: Bool
        public init(id: String, journalId: String, title: String, bodyText: String, bodyJson: String?, labels: [String], createdAt: Double, updatedAt: Double, attachments: [JSONValue], deleted: Bool) {
            self.id = id; self.journalId = journalId; self.title = title; self.bodyText = bodyText; self.bodyJson = bodyJson; self.labels = labels
            self.createdAt = createdAt; self.updatedAt = updatedAt; self.attachments = attachments; self.deleted = deleted } }
    public struct File { public let path: String; public let data: Data; public let mtime: Double? }
    public struct Summary: Equatable, Sendable { public let filename: String; public let entries, media, missingMedia: Int }
    /// web ExportProgress: `done` of `total` steps (one per entry and per media reference).
    public struct Progress: Equatable, Sendable { public let done, total: Int; public let current: String }

    public static func entries(_ records: [VaultRecord]) -> [Entry] {
        records.filter { $0.kind == "entry" }.map { r in
            let created = r.body["createdAt"]?.number ?? Double(r.clock)
            return Entry(id: r.id, journalId: r.body["journalId"]?.string ?? "", title: r.body["title"]?.string ?? "", bodyText: r.body["bodyText"]?.string ?? "",
                         bodyJson: r.body["bodyJson"]?.string, labels: r.body["labels"]?.array.compactMap { $0.string } ?? [], createdAt: created,
                         updatedAt: r.body["updatedAt"]?.number ?? created, attachments: r.body["attachments"]?.array ?? [], deleted: r.deleted)
        }
    }

    // MARK: JavaScript helpers
    /// `Number(x)` for the values node attrs can hold.
    static func jsNumber(_ v: JSONValue) -> Double {
        switch v {
        case .number(let n): return n
        case .bool(let b): return b ? 1 : 0
        case .null: return 0
        case .string(let s):
            let t = s.trimmingCharacters(in: EntryLinkAuthoring.ecmaWhitespace)
            return t.isEmpty ? 0 : (Double(t) ?? .nan)
        default: return .nan
        }
    }
    /// `new Date(ms).toISOString()`, or nil when the time is invalid.
    public static func iso(_ ms: Double?) -> String? {
        guard let ms, ms.isFinite, abs(ms) <= 8.64e15 else { return nil }
        let t = Int64(ms.rounded(.towardZero))
        let days = Int64((Double(t) / 86_400_000).rounded(.down)), msOfDay = t - days * 86_400_000
        // Civil-from-days (proleptic Gregorian, UTC).
        let z = days + 719_468, era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097, yoe = (doe - doe / 1460 + doe / 36524 - doe / 146_096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100), mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1, m = mp < 10 ? mp + 3 : mp - 9, y = yoe + era * 400 + (m <= 2 ? 1 : 0)
        func pad(_ n: Int64, _ w: Int) -> String { let s = String(n); return String(repeating: "0", count: max(0, w - s.count)) + s }
        let year = (0...9999).contains(y) ? pad(y, 4) : (y < 0 ? "-" : "+") + pad(abs(y), 6)
        let h = msOfDay / 3_600_000, mi = msOfDay / 60_000 % 60, s = msOfDay / 1000 % 60, f = msOfDay % 1000
        return "\(year)-\(pad(m, 2))-\(pad(d, 2))T\(pad(h, 2)):\(pad(mi, 2)):\(pad(s, 2)).\(pad(f, 3))Z"
    }
    /// export/journal.ts `slugify`.
    public static func slugify(_ name: String) -> String {
        let folded = String(String.UnicodeScalarView(name.decomposedStringWithCompatibilityMapping.unicodeScalars.filter { !(0x300...0x36F).contains($0.value) }))
        var out = ""; var dash = false
        for c in ChapterSearch.jsLower(folded).unicodeScalars {
            if ("a"..."z").contains(c) || ("0"..."9").contains(c) { out.unicodeScalars.append(c); dash = false } else if !dash { out += "-"; dash = true }
        }
        while out.hasPrefix("-") { out.removeFirst() }
        while out.hasSuffix("-") { out.removeLast() }
        let slug = String(out.prefix(48))
        return slug.isEmpty ? "journal" : slug
    }
    static func safeID(_ id: String, _ index: Int) -> String {
        let cleaned = String(String.UnicodeScalarView(id.unicodeScalars.filter { ("A"..."Z").contains($0) || ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "_" || $0 == "-" }).prefix(64))
        return cleaned.isEmpty ? "media-\(index)" : cleaned
    }
    static let extensions: [String: String] = ["video/webm": "webm", "video/mp4": "mp4", "video/quicktime": "mov", "audio/mp4": "m4a", "audio/mpeg": "mp3", "audio/webm": "weba", "audio/ogg": "ogg", "audio/wav": "wav", "audio/x-wav": "wav", "image/jpeg": "jpg", "image/png": "png", "image/webp": "webp", "image/gif": "gif", "image/avif": "avif", "image/heic": "heic", "application/pdf": "pdf", "text/plain": "txt", "text/markdown": "md", "application/json": "json", "application/zip": "zip"]
    static func extensionFor(_ att: JSONValue) -> String {
        let mime = att["mime"].string ?? ""
        let base = ChapterSearch.jsLower(String(mime.split(separator: ";", omittingEmptySubsequences: false).first ?? "").trimmingCharacters(in: EntryLinkAuthoring.ecmaWhitespace))
        if let known = extensions[base] { return known }
        let name = att["name"].string ?? ""
        if let dot = name.lastIndex(of: ".") {
            let ext = name[name.index(after: dot)...]
            if (1...8).contains(ext.count), ext.unicodeScalars.allSatisfy({ ("A"..."Z").contains($0) || ("a"..."z").contains($0) || ("0"..."9").contains($0) }) { return ext.lowercased() }
        }
        return "bin"
    }

    // MARK: collect.ts
    /// `coerce`: node attrs back into a media attachment (every field defended).
    static func coerce(_ raw: JSONValue, forceKind: String? = nil) -> JSONValue? {
        guard case .object = raw, let id = raw["id"].string, !id.isEmpty else { return nil }
        let k = raw["kind"].string
        var out: [String: JSONValue] = ["id": .string(id), "kind": .string(forceKind ?? (k == "audio" || k == "image" || k == "file" ? k! : "video")),
                                        "mime": .string(raw["mime"].string ?? ""), "createdAt": .number(jsNumber(raw["createdAt"]))]
        for key in ["durationMs", "width", "height"] { if case .number = raw[key] { out[key] = raw[key] } }
        if let name = raw["name"].string, !name.isEmpty { out["name"] = .string(name) }
        return .object(out)
    }
    /// `docAttachments`: every media reference in document order, deduplicated by id.
    public static func docAttachments(_ doc: JSONValue) -> [JSONValue] {
        var out: [JSONValue] = []; var seen = Set<String>()
        func push(_ a: JSONValue?) { if let a, let id = a["id"].string, seen.insert(id).inserted { out.append(a) } }
        func walk(_ node: JSONValue) {
            switch node { case .object, .array: break; default: return }
            let attrs: JSONValue = { if case .object = node["attrs"] { return node["attrs"] }; return .object([:]) }()
            switch node["type"].string {
            case "mediaAttachment": push(coerce(attrs))
            case "mediaGallery": attrs["images"].array.forEach { push(coerce($0, forceKind: "image")) }
            case "locationMap": push(coerce(attrs["map"], forceKind: "image")); push(coerce(attrs["photo"], forceKind: "image"))
            case "videoInterview":
                for card in attrs["cards"].array { if case .object = card { push(coerce(card["clip"])) } }
                push(coerce(attrs["film"]))
            default: break
            }
            node["content"].array.forEach(walk)
        }
        walk(doc); return out
    }
    /// `docLinks`: entryLink targets in document order.
    public static func docLinks(_ doc: JSONValue) -> [String] {
        var out: [String] = []
        func walk(_ node: JSONValue) {
            if node["type"].string == "entryLink", let id = node["attrs"]["entryId"].string, !id.isEmpty { out.append(id) }
            node["content"].array.forEach(walk)
        }
        walk(doc); return out
    }
    /// `parseDoc`: the stored body when JSON.parse gives an object or array, else the text as
    /// paragraphs (split on "\n" alone, like JavaScript, so a "\r" stays in its line).
    public static func parseDoc(_ e: Entry) -> JSValue {
        if let json = e.bodyJson, !json.isEmpty, let v = try? JSValue.parse(json) {
            switch v { case .object, .array: return v; default: break }
        }
        let lines = ChapterMarkdown.lines(e.bodyText).map { line -> JSValue in
            line.isEmpty ? .object([("type", .string("paragraph"))]) : .object([("type", .string("paragraph")), ("content", .array([.object([("type", .string("text")), ("text", .string(line))])]))])
        }
        return .object([("type", .string("doc")), ("content", .array(lines))])
    }
    /// JSON.stringify writes non-finite numbers as null.
    static func finite(_ v: JSONValue) -> JSONValue {
        switch v {
        case .number(let n): return n.isFinite ? v : .null
        case .array(let a): return .array(a.map(finite))
        case .object(let o): return .object(o.mapValues(finite))
        default: return v
        }
    }

    static func json(_ v: JSONValue) throws -> Data {
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try enc.encode(finite(v))
    }

    /// web `mneme-<slug>-<YYYY-MM-DD>.zip` (the UTC export date).
    public static func filename(name: String, now: Double) -> String { "mneme-\(slugify(name))-\((iso(now) ?? "1970-01-01").prefix(10)).zip" }

    /// The whole export written to `url` as a zip, off the caller's actor. `media` returning nil
    /// records a missing file; throwing aborts (for example when the vault locks).
    public static func writeZip(to url: URL, journal: Journal, entries: [Entry], now: Double, generator: (app: String, version: String),
                                media: @escaping @Sendable (_ entryID: String, _ attachment: JSONValue) async throws -> Data?,
                                progress: @escaping @Sendable (Progress) -> Void) async throws -> Summary {
        let writer = try ChapterZipWriter(url: url, fallbackMtime: now)
        let summary = try await archive(journal: journal, entries: entries, now: now, generator: generator, media: media, progress: progress) {
            try writer.add(path: $0.path, data: $0.data, mtime: $0.mtime)
        }
        try writer.finish()
        return summary
    }

    /// `exportJournal`, streamed: each file goes to `emit` as soon as it exists, so media is
    /// held one file at a time. `media` returns decrypted bytes or nil (recorded as missing,
    /// never fatal); `progress` mirrors the web's.
    public static func archive(journal: Journal, entries all: [Entry], now: Double, generator: (app: String, version: String),
                               media: (_ entryID: String, _ attachment: JSONValue) async throws -> Data?,
                               progress: (Progress) -> Void = { _ in }, emit: (File) throws -> Void) async throws -> Summary {
        let entries = all.enumerated().filter { $0.element.journalId == journal.id && !$0.element.deleted }
            .sorted { $0.element.createdAt != $1.element.createdAt ? $0.element.createdAt < $1.element.createdAt : $0.offset < $1.offset }.map(\.element)
        let nowISO = iso(now) ?? "1970-01-01T00:00:00.000Z"
        var refs: [JSONValue] = [], mediaList: [JSONValue] = [], missing: [JSONValue] = []
        var written: [String: JSONValue] = [:]
        let plan = entries.map { entry -> (Entry, JSValue, [JSONValue]) in
            let parsed = parseDoc(entry)
            let inline = docAttachments(parsed.jsonValue)
            let seen = Set(inline.compactMap { $0["id"].string })
            let legacy = entry.attachments.filter { a in if let id = a["id"].string, !id.isEmpty { return true }; return false }
            return (entry, parsed, inline + legacy.filter { !seen.contains($0["id"].string ?? "") })
        }
        let total = plan.count + plan.reduce(0) { $0 + $1.2.count }
        var done = 0
        func step(_ current: String) { done += 1; progress(Progress(done: done, total: total, current: current)) }
        for (entry, parsed, attachments) in plan {
            let doc = parsed.jsonValue
            let entryPath = "entries/\(safeID(entry.id, refs.count)).json"
            var entryMedia: [JSONValue] = []
            for (i, att) in attachments.enumerated() {
                let path = "media/\(safeID(att["id"].string ?? "", i)).\(extensionFor(att))"
                let label = att["name"].string.flatMap { $0.isEmpty ? nil : $0 } ?? path
                if let already = written[path] { entryMedia.append(already); step(label); continue }
                guard let bytes = try await media(entry.id, att) else {
                    missing.append(.object(["id": att["id"], "entryId": .string(entry.id), "reason": .string("unavailable")])); step(label); continue
                }
                let created: Double? = { if case .number(let n) = att["createdAt"] { return n }; return nil }()
                try emit(File(path: path, data: bytes, mtime: created))
                var record: [String: JSONValue] = ["id": att["id"], "path": .string(path), "bytes": .number(Double(bytes.count)),
                                                   "createdAt": .string(iso(created) ?? iso(entry.createdAt) ?? nowISO), "entryId": .string(entry.id)]
                for key in ["kind", "mime", "name", "durationMs", "width", "height"] { if case .object(let o) = att, let v = o[key] { record[key] = v } }
                written[path] = .object(record); mediaList.append(.object(record)); entryMedia.append(.object(record)); step(label)
            }
            let created = iso(entry.createdAt) ?? nowISO, updated = iso(entry.updatedAt) ?? iso(entry.createdAt) ?? nowISO
            let payload: JSONValue = .object(["id": .string(entry.id), "journalId": .string(entry.journalId), "title": .string(entry.title), "createdAt": .string(created),
                                              "updatedAt": .string(updated), "labels": .array(entry.labels.map(JSONValue.string)), "body": doc,
                                              "markdown": .string((try? ChapterMarkdown.docToMarkdown(parsed)) ?? entry.bodyText), "media": .array(entryMedia), "links": .array(docLinks(doc).map(JSONValue.string))])
            try emit(File(path: entryPath, data: try json(payload), mtime: entry.updatedAt))
            refs.append(.object(["id": .string(entry.id), "path": .string(entryPath), "title": .string(entry.title), "createdAt": .string(created), "updatedAt": .string(updated),
                                 "labels": .array(entry.labels.map(JSONValue.string)), "media": .array(entryMedia.map { $0["id"] })]))
            step(entry.title)
        }
        var meta: [String: JSONValue] = ["id": .string(journal.id), "name": .string(journal.name)]
        if !journal.subtitle.isEmpty { meta["subtitle"] = .string(journal.subtitle) }
        if !journal.color.isEmpty { meta["color"] = .string(journal.color) }
        if !journal.cover.isEmpty { meta["cover"] = .string(journal.cover) }
        if let c = iso(journal.createdAt) { meta["createdAt"] = .string(c) }
        if let u = iso(journal.updatedAt) { meta["updatedAt"] = .string(u) }
        let manifest: JSONValue = .object(["format": .string("mneme-journal-export"), "formatVersion": .number(1),
            "generator": .object(["app": .string(generator.app), "version": .string(generator.version)]), "exportedAt": .string(nowISO), "journal": .object(meta),
            "counts": .object(["entries": .number(Double(refs.count)), "media": .number(Double(mediaList.count)), "missingMedia": .number(Double(missing.count))]),
            "entries": .array(refs), "media": .array(mediaList), "missingMedia": .array(missing)])
        try emit(File(path: "mneme-export.json", data: try json(manifest), mtime: now))
        try emit(File(path: "README.md", data: Data(readme(name: journal.name, exportedAt: nowISO, entries: refs.count, media: mediaList.count, missing: missing.count).utf8), mtime: now))
        return Summary(filename: filename(name: journal.name, now: now), entries: refs.count, media: mediaList.count, missingMedia: missing.count)
    }

    static func readme(name: String, exportedAt: String, entries: Int, media: Int, missing: Int) -> String {
        func plural(_ n: Int, _ one: String, _ many: String) -> String { "\(n) \(n == 1 ? one : many)" }
        let incomplete = missing > 0 ? """

        ## Incomplete

        \(plural(missing, "media file", "media files")) could not be included — not on the
        device that made this export, and not fetchable. They are listed under
        `missingMedia` in the manifest. Export again from a device that holds them, or
        while online, to get a complete archive.

        """ : ""
        return """
        # \(name)

        A Mneme journal export — \(plural(entries, "entry", "entries")) and \(plural(media, "media file", "media files")),
        written on \(exportedAt.prefix(10)).

        This archive holds your **decrypted** content. Treat it like the journal itself.

        ## Layout

        - `mneme-export.json` — the table of contents: the journal, every entry, every media file.
        - `entries/<id>.json` — one file per entry. `body` is the content of record (a
          ProseMirror/TipTap document); `markdown` is the same thing rendered readably.
        - `media/<id>.<ext>` — the pictures, recordings and attachments, decrypted.

        ## Format

        `mneme-journal-export`, version 1. The full specification — every field and
        every document node type — is at:

          https://github.com/mneme-blog/mneme/blob/main/docs/EXPORT-FORMAT.md

        It is a stable, documented format: anyone can write an importer for it.

        """ + incomplete
    }
}

/// A streaming, store-only (method 0) ZIP writer with UTF-8 names and CRC-32. Media is
/// already compressed and the web stores it the same way; JSON is stored too, which any
/// unzip tool reads. No ZIP64: more than 65,535 files or 4 GiB is refused, never truncated.
public final class ChapterZipWriter {
    private let handle: FileHandle
    private var central = Data(), count = 0, offset: UInt64 = 0
    private let fallbackMtime: Double?
    /// `fallbackMtime` (the export time) stands in for a time a zip can't hold, like the web ArchiveWriter.
    public init(url: URL, fallbackMtime: Double? = nil) throws {
        self.fallbackMtime = fallbackMtime
        guard FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.protectionKey: FileProtectionType.complete]) || FileManager.default.createFile(atPath: url.path, contents: nil) else { throw ChapterError.storage }
        handle = try FileHandle(forWritingTo: url)
    }
    static let crcTable: [UInt32] = (0..<256).map { i -> UInt32 in var c = UInt32(i); for _ in 0..<8 { c = c & 1 != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1 }; return c }
    public static func crc32(_ data: Data) -> UInt32 { var c: UInt32 = 0xFFFFFFFF; for b in data { c = crcTable[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8) }; return c ^ 0xFFFFFFFF }
    /// DOS date/time in local time like fflate, or nil outside 1980–2099 (the range the web writes).
    static func dos(_ ms: Double?) -> (time: UInt16, date: UInt16)? {
        guard let ms, ms.isFinite, abs(ms) <= 8.64e15 else { return nil }
        let p = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day, .hour, .minute, .second], from: Date(timeIntervalSince1970: ms / 1000))
        guard let y = p.year, (1980...2099).contains(y) else { return nil }
        // Typed one part at a time: as a single expression it exceeds Xcode 16.4's type-checker budget.
        let hour: Int = p.hour ?? 0, minute: Int = p.minute ?? 0, second: Int = p.second ?? 0
        let month: Int = p.month ?? 1, day: Int = p.day ?? 1
        let time: Int = (hour << 11) | (minute << 5) | (second / 2)
        let date: Int = ((y - 1980) << 9) | (month << 5) | day
        return (UInt16(time), UInt16(date))
    }
    private func le<T: FixedWidthInteger>(_ v: T, _ d: inout Data) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
    public func add(path: String, data: Data, mtime: Double?) throws {
        let name = Data(path.utf8)
        guard count < 0xFFFF, data.count < 0xFFFF_FFFF, offset < 0xFFFF_FFFF, name.count < 0xFFFF else { throw ChapterError.unsupported }
        let crc = Self.crc32(data), t = Self.dos(mtime) ?? Self.dos(fallbackMtime) ?? Self.dos(Date().timeIntervalSince1970 * 1000) ?? (0, 0x21)
        var local = Data(); le(UInt32(0x04034b50), &local); le(UInt16(20), &local); le(UInt16(0x0800), &local); le(UInt16(0), &local)
        le(t.time, &local); le(t.date, &local); le(crc, &local); le(UInt32(data.count), &local); le(UInt32(data.count), &local)
        le(UInt16(name.count), &local); le(UInt16(0), &local); local.append(name)
        var c = Data(); le(UInt32(0x02014b50), &c); le(UInt16(20), &c); le(UInt16(20), &c); le(UInt16(0x0800), &c); le(UInt16(0), &c)
        le(t.time, &c); le(t.date, &c); le(crc, &c); le(UInt32(data.count), &c); le(UInt32(data.count), &c)
        le(UInt16(name.count), &c); le(UInt16(0), &c); le(UInt16(0), &c); le(UInt16(0), &c); le(UInt16(0), &c); le(UInt32(0), &c); le(UInt32(offset), &c); c.append(name)
        try handle.write(contentsOf: local); try handle.write(contentsOf: data)
        offset += UInt64(local.count + data.count); central.append(c); count += 1
        guard offset < 0xFFFF_FFFF else { throw ChapterError.unsupported }
    }
    deinit { if !finished { try? handle.close() } }
    private var finished = false
    public func finish() throws {
        finished = true
        var end = Data(); le(UInt32(0x06054b50), &end); le(UInt16(0), &end); le(UInt16(0), &end); le(UInt16(count), &end); le(UInt16(count), &end)
        le(UInt32(central.count), &end); le(UInt32(offset), &end); le(UInt16(0), &end)
        try handle.write(contentsOf: central); try handle.write(contentsOf: end); try handle.close()
    }
}
