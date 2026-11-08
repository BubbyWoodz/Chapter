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
        return doc == expected
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
    public static func plainDocument(_ text: String) throws -> String {
        let paragraphs = text.components(separatedBy: "\n").map { line -> JSONValue in
            .object(["type": .string("paragraph"), "content": .array(line.isEmpty ? [] : [.object(["type": .string("text"), "text": .string(line)])])])
        }
        let doc: JSONValue = .object(["type": .string("doc"), "content": .array(paragraphs)])
        return String(decoding: try JSONEncoder().encode(doc), as: UTF8.self)
    }
}

public struct VaultSnapshot: Codable, Equatable {
    public var version = 1
    public var records: [VaultRecord] = []
    public var cursor: Int64 = 0
    public var conflicts: [VaultRecord] = []
    public init() {}
    public mutating func acknowledge(_ sent: VaultRecord) {
        // An in-flight response cannot mark a newer local edit clean.
        if let i = records.firstIndex(where: { $0.id == sent.id && $0.clock == sent.clock && $0.body == sent.body && $0.deleted == sent.deleted }) { records[i].dirty = false }
    }
    public mutating func merge(_ remote: VaultRecord) {
        if let i = records.firstIndex(where: { $0.id == remote.id }) {
            let local = records[i]
            if remote.clock == local.clock {
                if local.body == remote.body && local.deleted == remote.deleted {
                    // A lost push response is confirmed by the next authenticated pull.
                    records[i].dirty = false
                } else if local.dirty && !conflicts.contains(remote) {
                    conflicts.append(remote) // retain both sides of an equal-clock collision
                }
                return
            }
            guard remote.clock > local.clock else { return }
            if local.dirty && (local.body != remote.body || local.deleted != remote.deleted) && !conflicts.contains(local) { conflicts.append(local) }
            records[i] = remote
        } else { records.append(remote) }
    }
}
