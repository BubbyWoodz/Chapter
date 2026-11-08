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

public struct VaultRecord: Codable, Identifiable, Equatable {
    public var id: String
    public var clock: Int64
    public var deleted: Bool
    public var body: [String: JSONValue]
    public var dirty: Bool
    public var kind: String { body["kind"]?.string ?? "entry" }
    public var title: String { body["title"]?.string ?? body["name"]?.string ?? "Untitled" }
    public var text: String { body["bodyText"]?.string ?? "" }
    public var journalID: String { body["journalId"]?.string ?? "" }
    public var date: Date { Date(timeIntervalSince1970: (body["createdAt"]?.number ?? Double(clock)) / 1000) }
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
        if let i = records.firstIndex(where: { $0.id == sent.id && $0.clock == sent.clock }) { records[i].dirty = false }
    }
    public mutating func merge(_ remote: VaultRecord) {
        if let i = records.firstIndex(where: { $0.id == remote.id }) {
            let local = records[i]
            guard remote.clock > local.clock else { return }
            if local.dirty && local.body != remote.body && !conflicts.contains(local) { conflicts.append(local) }
            records[i] = remote
        } else { records.append(remote) }
    }
}
