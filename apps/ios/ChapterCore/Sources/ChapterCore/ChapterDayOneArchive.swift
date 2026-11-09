// SPDX-License-Identifier: AGPL-3.0-or-later
// Port of the web importer's parseDayOneArchive / entryMoments (apps/client/src/import/dayone.ts).
// The parsed JSON stays a JSValue so loose JavaScript behaviour carries over exactly: a null
// entry or moment, or a non-iterable `photos`, throws (the web rejects with a TypeError), a
// string `photos` iterates to nothing, and template strings stringify like JavaScript.
// Deliberate difference: the web inflates every member up front; media members here are
// inflated only when resolved (a large export would not fit in an iPhone's memory), so a
// corrupt media member fails at resolve time with the same "not a valid .zip" error.
import Foundation

public struct DayOneArchive {
    public typealias MomentKind = ChapterDayOne.MomentKind
    public struct Journal { public let name: String; public let entries: [JSValue] }
    public struct Moment { public let moment: JSValue; public let kind: MomentKind }
    /// One resolved moment, ready for the media upload path. `mime` is the type a web Blob would carry.
    public struct Resolved {
        public let identifier: JSValue?, kind: MomentKind, data: Data, mime: String, name: String
        public let width: JSValue?, height: JSValue?, durationMs: Double?
    }
    public enum ImportError: Error, Equatable, LocalizedError {
        case notZip, noJournal, malformed
        public var errorDescription: String? {
            switch self {
            case .notZip: return "This file is not a valid .zip — export your Day One journal as JSON and pick the .zip it produces."
            case .noJournal: return "No Day One journal JSON found in the zip. Make sure you exported as JSON, not PDF or plain text."
            case .malformed: return "This Day One export contains an entry Chapter can't read, so nothing was imported."
            }
        }
    }

    public let journals: [Journal]
    public let entryCount: Int
    public let mediaCount: Int
    let reader: ChapterZipReader
    // Keys are UTF-16 units: JavaScript Map keys are exact strings, while Swift `==` merges
    // canonically equivalent text (U+212A KELVIN SIGN == "K").
    let byBasename: [[UInt16]: ChapterZipReader.Member]
    let byStem: [[UInt16]: ChapterZipReader.Member]

    static let extMime: [String: String] = [
        "jpeg": "image/jpeg", "jpg": "image/jpeg", "png": "image/png", "gif": "image/gif",
        "heic": "image/heic", "heif": "image/heif", "webp": "image/webp", "tiff": "image/tiff",
        "mov": "video/quicktime", "mp4": "video/mp4", "m4v": "video/x-m4v", "avi": "video/x-msvideo",
        "m4a": "audio/mp4", "aac": "audio/aac", "mp3": "audio/mpeg", "wav": "audio/wav", "aiff": "audio/aiff",
        "pdf": "application/pdf",
        // EXT_MIME is a plain object literal, so these resolve to Object.prototype members on the web;
        // these strings are what `new Blob([...], { type })` then carries.
        "constructor": "function object() { [native code] }", "__proto__": "[object object]",
    ]
    static func folder(_ k: MomentKind) -> String { switch k { case .image: return "photos"; case .video: return "videos"; case .audio: return "audios"; case .file: return "pdfs" } }
    static let kinds: [(String, MomentKind)] = [("photos", .image), ("videos", .video), ("audios", .audio), ("pdfAttachments", .file)]
    static let jsonLimit = 256 << 20

    public init(_ zip: Data) throws {
        guard let reader = try? ChapterZipReader(zip), reader.members.allSatisfy({ $0.method == 0 || $0.method == 8 }) else { throw ImportError.notZip }
        self.reader = reader
        var byBasename: [[UInt16]: ChapterZipReader.Member] = [:], byStem: [[UInt16]: ChapterZipReader.Member] = [:]
        var journals: [Journal] = []
        for path in reader.jsOrderedNames {
            guard let member = reader.last(named: path) else { continue }
            let p = Array(path.utf16)
            if p.last == 0x2F || member.size == 0 { continue }
            let base = Array(p[((p.lastIndex(of: 0x2F)).map { $0 + 1 } ?? 0)...])
            if Self.hasJSONSuffix(base) {
                guard let bytes = try? reader.contents(member, limit: Self.jsonLimit) else { throw ImportError.notZip }
                var text = String(decoding: bytes, as: UTF8.self)
                if text.hasPrefix("\u{FEFF}") { text.removeFirst() } // TextDecoder drops a UTF-8 BOM
                guard let parsed = try? JSValue.parse(text) else { continue }
                if parsed == .null { throw ImportError.malformed } // `null.entries`
                guard case .array(let entries)? = parsed.get("entries") else { continue }
                let stem = String(decoding: base.dropLast(5), as: UTF16.self)
                journals.append(Journal(name: stem.isEmpty ? "Imported" : stem, entries: entries))
                continue
            }
            byBasename[base] = member
            if let dot = base.lastIndex(of: 0x2E), dot > 0 { byStem[Array(base[..<dot])] = member } else { byStem[base] = member }
        }
        guard !journals.isEmpty else { throw ImportError.noJournal }
        self.journals = journals; self.byBasename = byBasename; self.byStem = byStem
        var entries = 0, media = 0
        for j in journals {
            entries += j.entries.count
            for e in j.entries {
                for (key, _) in Self.kinds {
                    for m in try Self.iterate(try Self.prop(e, key)) where try Self.find(m, byBasename, byStem) != nil { media += 1 }
                }
            }
        }
        entryCount = entries; mediaCount = media
    }

    static func hasJSONSuffix(_ b: [UInt16]) -> Bool {
        guard b.count >= 5 else { return false }
        let tail = b.suffix(5).map { $0 >= 0x41 && $0 <= 0x5A ? $0 + 0x20 : $0 }
        return tail == Array(".json".utf16)
    }
    static func prop(_ v: JSValue?, _ key: String) throws -> JSValue? {
        do { return try JSValue.prop(v, key) } catch { throw ImportError.malformed }
    }
    /// `for (const m of arr ?? [])`: strings iterate characters (none of which has a moment's fields).
    static func iterate(_ v: JSValue?) throws -> [JSValue] {
        switch v {
        case nil, .null?, .string?: return []
        case .array(let a)?: return a
        default: throw ImportError.malformed
        }
    }
    /// `${v}` in a template literal.
    static func template(_ v: JSValue?) -> String { v.map(JSValue.toString) ?? "undefined" }
    static func find(_ m: JSValue, _ byBasename: [[UInt16]: ChapterZipReader.Member], _ byStem: [[UInt16]: ChapterZipReader.Member]) throws -> ChapterZipReader.Member? {
        if m == .null { throw ImportError.malformed } // `const { md5, type } = null`
        let md5 = m.get("md5"), type = m.get("type"), id = m.get("identifier")
        if JSValue.truthy(md5), JSValue.truthy(type), let x = byBasename[Array((template(md5) + "." + template(type)).utf16)] { return x }
        if JSValue.truthy(md5), case .string(let s)? = md5, let x = byStem[Array(s.utf16)] { return x }
        if case .string(let s)? = id, let x = byStem[Array(s.utf16)] { return x }
        if JSValue.truthy(type), let x = byBasename[Array((template(id) + "." + template(type)).utf16)] { return x }
        return nil
    }

    /// `archive.resolve(moment, kind)`: nil when the file is missing from the archive.
    public func resolve(_ m: JSValue, _ kind: MomentKind) throws -> Resolved? {
        guard let member = try Self.find(m, byBasename, byStem) else { return nil }
        let ext: String
        switch m.get("type") {
        case nil, .null?: ext = ""
        case .string(let s)?: ext = s.lowercased()
        default: throw ImportError.malformed // toLowerCase is not a function
        }
        let mime = ext.isEmpty ? nil : Self.extMime[ext]
        let md5 = m.get("md5")
        let source = (md5 == nil || md5 == .null) ? m.get("identifier") : md5
        let short: String
        switch source {
        case .string(let s)?: short = String(decoding: Array(s.utf16.prefix(8)), as: UTF16.self)
        case .array(let a)?: short = JSValue.toString(.array(Array(a.prefix(8))))
        default: throw ImportError.malformed // undefined.slice / no slice method
        }
        var durationMs: Double?
        if case .number(let d)? = m.get("duration") { durationMs = Self.jsRound(d * 1000) }
        let data: Data
        do { data = try reader.contents(member) } catch { throw ImportError.notZip }
        return Resolved(
            identifier: m.get("identifier"), kind: kind, data: data,
            mime: mime ?? (kind == .image ? "image/jpeg" : kind == .video ? "video/quicktime" : kind == .audio ? "audio/mp4" : "application/octet-stream"),
            name: "\(Self.folder(kind))-\(short)\(ext.isEmpty ? "" : "." + ext)",
            width: m.get("width"), height: m.get("height"), durationMs: durationMs)
    }

    /// `Math.round`: halves go toward +∞, and negative results that round to zero stay -0.
    static func jsRound(_ x: Double) -> Double {
        guard x.isFinite else { return x }
        let f = x.rounded(.down)
        let r = x - f >= 0.5 ? f + 1 : f
        return r == 0 && x.sign == .minus ? -0.0 : r
    }

    /// `entryMoments(entry)`: identifier → moment, last one wins. Only string identifiers can be
    /// found later (the web looks them up by `String(identifier)` from a moment URL).
    public static func entryMoments(_ entry: JSValue) throws -> [[UInt16]: Moment] {
        var map: [[UInt16]: Moment] = [:]
        for (key, kind) in kinds {
            for m in try iterate(try prop(entry, key)) {
                if m == .null { throw ImportError.malformed }
                if case .string(let s)? = m.get("identifier"), !s.isEmpty { map[Array(s.utf16)] = Moment(moment: m, kind: kind) }
            }
        }
        return map
    }
}
