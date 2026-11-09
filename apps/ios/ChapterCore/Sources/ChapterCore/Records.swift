// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

// Preserve every unknown field and custom document node rather than flattening rich entries.
public enum JSONValue: Codable, Equatable {
    case object([String: JSONValue]), array([JSONValue]), string(String), number(Double), bool(Bool), null
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([String: JSONValue].self) { self = .object(v) }
        else { self = .array(try c.decode([JSONValue].self)) }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
    public var string: String? { if case .string(let v) = self { return v }; return nil }
    public var number: Double? { if case .number(let v) = self { return v }; return nil }
    public var array: [JSONValue] { if case .array(let v) = self { return v }; return [] }
    public subscript(_ key: String) -> JSONValue { if case .object(let v) = self { return v[key] ?? .null }; return .null }
}

// Wire clocks must also round-trip exactly through the existing JavaScript client.
// Reject instead of saturating/wrapping: either could falsely acknowledge a newer edit.
public enum ProtocolNumbers {
    public static let maxWireInteger: Int64 = 9_007_199_254_740_991
    public static func validate(_ value: Int64) throws {
        guard value >= 0, value <= maxWireInteger else { throw ChapterError.invalidClock }
    }
    public static func nextClock(after previous: Int64, now: Date = Date()) throws -> Int64 {
        try validate(previous)
        let milliseconds = (now.timeIntervalSince1970 * 1000).rounded(.down)
        guard milliseconds.isFinite, let wall = Int64(exactly: milliseconds) else { throw ChapterError.invalidClock }
        try validate(wall)
        let (successor, overflow) = previous.addingReportingOverflow(1)
        guard !overflow, successor <= maxWireInteger else { throw ChapterError.invalidClock }
        return max(wall, successor)
    }
    // Keep original JSON untouched; only bound presentation before Foundation calendar APIs.
    public static func displayDate(milliseconds: Double?) -> Date {
        guard let milliseconds, milliseconds.isFinite,
              (-62_135_596_800_000...253_402_300_799_999).contains(milliseconds) else {
            return Date(timeIntervalSince1970: 0)
        }
        return Date(timeIntervalSince1970: milliseconds / 1000)
    }
}

public struct VaultRecord: Codable, Identifiable, Equatable {
    public var id: String
    public var clock: Int64
    public var deleted: Bool
    public var body: [String: JSONValue]
    public var dirty: Bool
    public var kind: String { body["kind"]?.string ?? "entry" }
    public var title: String { body["title"]?.string ?? body["name"]?.string ?? "Untitled" }
    public var text: String { body["bodyText"]?.string ?? "" }
    public var labels: [String] { (body["labels"]?.array ?? []).compactMap { $0.string } }
    public var journalID: String { body["journalId"]?.string ?? "" }
    public var date: Date { ProtocolNumbers.displayDate(milliseconds: body["createdAt"]?.number ?? Double(clock)) }
    public init(id: String, clock: Int64, deleted: Bool = false, body: [String: JSONValue], dirty: Bool = false) {
        self.id = id; self.clock = clock; self.deleted = deleted; self.body = body; self.dirty = dirty
    }
    /// Swift String equality normalizes Unicode; original web JSON does not.
    /// Compare deterministic encoded payload bytes, ignoring only delivery state.
    /// Encoding failure is NOT evidence that either version has been delivered.
    public func hasSamePayload(as other: VaultRecord) -> Bool {
        guard deleted == other.deleted else { return false }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        guard let left = try? encoder.encode(body), let right = try? encoder.encode(other.body) else { return false }
        return left == right
    }
    public func hasSameVersion(as other: VaultRecord) -> Bool {
        id.utf8.elementsEqual(other.id.utf8) && clock == other.clock && hasSamePayload(as: other)
    }
    public static func == (lhs: VaultRecord, rhs: VaultRecord) -> Bool {
        lhs.dirty == rhs.dirty && lhs.hasSameVersion(as: rhs)
    }
    // Only newly-created plain entries may use the plain editor. Other-client content is read-only.
    public var editablePlainText: Bool {
        guard kind == "entry", body["chapterNativePlain"] == .bool(true) else { return false }
        guard body["attachments"]?.array.isEmpty ?? true else { return false }
        guard let json = body["bodyJson"]?.string, let data = json.data(using: .utf8),
              let doc = try? JSONDecoder().decode(JSONValue.self, from: data) else { return false }
        // Strict canonical tree equality also rejects unknown attrs/marks and
        // media injected by another client, even when it kept our marker.
        guard let canonical = try? Self.plainDocument(text),
              let expected = try? JSONDecoder().decode(JSONValue.self, from: Data(canonical.utf8)) else { return false }
        let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
        guard let current=try? encoder.encode(doc),let plain=try? encoder.encode(expected) else {return false}
        return current == plain
    }
    public func restoredEntry(id: String, now: Date = Date()) throws -> VaultRecord {
        // A notebook/settings conflict cannot be restored by reusing its logical ID:
        // that would overwrite the current singleton instead of making a new entry.
        guard kind == "entry" else { throw ChapterError.unsupported }
        var copy = self
        copy.id = id; copy.clock = try ProtocolNumbers.nextClock(after: 0, now: now)
        copy.deleted = false; copy.dirty = true
        copy.body["updatedAt"] = .number(Double(copy.clock))
        return copy
    }
    public func requiringUnchanged(expected: VaultRecord) throws {
        // Canonically equivalent Swift Strings can still be distinct original
        // web data. Only delivery acknowledgement may differ from a checkpoint.
        guard hasSameVersion(as: expected) else { throw ChapterError.conflict }
    }
    /// Move without flattening rich content, changing dates, or reuploading media.
    public func movingEntry(expected: VaultRecord, to notebook: VaultRecord, now: Date = Date()) throws -> VaultRecord {
        guard kind == "entry", !deleted, notebook.kind == "journal", !notebook.deleted, !notebook.journalID.isEmpty else { throw ChapterError.unsupported }
        try requiringUnchanged(expected: expected)
        guard journalID != notebook.journalID else { return self }
        var next = self; next.clock = try ProtocolNumbers.nextClock(after: clock, now: now)
        next.body["journalId"] = .string(notebook.journalID); next.body["updatedAt"] = .number(Double(next.clock)); next.dirty = true
        return next
    }
    /// Patch only the original browser notebook fields, preserving opaque future data.
    /// Compare against the editor's opening value; an ack may change dirty, not body.
    public func editingJournal(expected: VaultRecord, name: String? = nil, subtitle: String? = nil,
                               color: String? = nil, cover: String? = nil, now: Date = Date()) throws -> VaultRecord {
        guard kind == "journal", !deleted, !journalID.isEmpty else { throw ChapterError.unsupported }
        try requiringUnchanged(expected: expected)
        var copy = self
        if let name {
            let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, value.count <= 200 else { throw ChapterError.unsupported }
            copy.body["name"] = .string(value)
        }
        if let subtitle {
            guard subtitle.count <= 2000 else { throw ChapterError.unsupported }
            copy.body["subtitle"] = .string(subtitle)
        }
        if let color {
            let bytes = Array(color.utf8)
            guard bytes.count == 7, bytes[0] == 35, bytes.dropFirst().allSatisfy({
                (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0)
            }) else { throw ChapterError.unsupported }
            copy.body["color"] = .string(color)
        }
        if let cover {
            guard ["lines", "dots", "grid", "plain", "photo"].contains(cover) else { throw ChapterError.unsupported }
            copy.body["cover"] = .string(cover)
        }
        guard !copy.hasSamePayload(as: self) else { return self }
        copy.clock = try ProtocolNumbers.nextClock(after: clock, now: now)
        copy.body["updatedAt"] = .number(Double(copy.clock)); copy.dirty = true
        return copy
    }
    public static func plainDocument(_ text: String) throws -> String {
        let paragraphs = text.components(separatedBy: "\n").map { line -> JSONValue in
            .object(["type": .string("paragraph"), "content": .array(line.isEmpty ? [] : [.object(["type": .string("text"), "text": .string(line)])])])
        }
        let doc: JSONValue = .object(["type": .string("doc"), "content": .array(paragraphs)])
        return String(decoding: try JSONEncoder().encode(doc), as: UTF8.self)
    }
}

public struct VaultSnapshot: Codable, Equatable {
    public var version = 4 // Local-only: older previews must fail closed, not discard rich drafts.
    public var records: [VaultRecord] = []
    public var cursor: Int64 = 0
    public var conflicts: [VaultRecord] = []
    public var mediaUploads: [MediaUpload]? = nil
    public var mediaCache: [MediaCache]? = nil
    public var richDrafts: [RichDraft]? = nil // Optional: old encrypted snapshots decode unchanged.
    public init() {}
    public mutating func acknowledge(_ sent: VaultRecord) {
        // An in-flight response cannot mark a newer local edit clean.
        if let i = records.firstIndex(where: { $0.hasSameVersion(as: sent) }) { records[i].dirty = false }
    }
    public mutating func merge(_ remote: VaultRecord) {
        if let i = records.firstIndex(where: { $0.id == remote.id }) {
            let local = records[i]
            if remote.clock == local.clock {
                if local.hasSamePayload(as: remote) {
                    // A lost push response is confirmed by the next authenticated pull.
                    records[i].dirty = false
                } else if !conflicts.contains(where: { $0.hasSameVersion(as: remote) }) {
                    conflicts.append(remote) // retain both sides of an equal-clock collision
                }
                return
            }
            guard remote.clock > local.clock else { return }
            if local.dirty && !local.hasSamePayload(as: remote) && !conflicts.contains(where: { $0.hasSameVersion(as: local) }) { conflicts.append(local) }
            records[i] = remote
        } else { records.append(remote) }
    }
}

/// Each ID is attempted once per pass, so rejected/stale records do not starve
/// later batches and an actively edited entry cannot create an infinite drain.
/// A newer edit during an in-flight acknowledgment stays dirty for the next pass.
public struct SyncPushQueue {
    private var attempted = Set<String>()
    private var batches = 0
    public init() {}
    public mutating func next(from snapshot: VaultSnapshot) throws -> [VaultRecord] {
        let seen = attempted
        let batch = Array(snapshot.uploadableRecords.lazy.filter { !seen.contains($0.id) }.prefix(100))
        guard !batch.isEmpty else { return [] }
        guard batches < 100 else { throw ChapterError.unsupported }
        batches += 1; attempted.formUnion(batch.map(\.id)); return batch
    }
}

/// Foreground-only retry policy; bounded arithmetic and no wall-clock dependency.
public struct SyncBackoff {
    public private(set) var seconds = 30
    public init() {}
    public mutating func succeeded() { seconds = 30 }
    public mutating func failed() { seconds = seconds >= 150 ? 300 : seconds * 2 }
}
