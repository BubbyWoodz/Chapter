// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

/// Port of the web interview-types manager (InterviewTypesSheet with
/// createInterviewType / updateInterviewType / deleteInterviewType through
/// mutateSeeded). A type is a name, a one-line intro and a prompt; the record body
/// is the web codec's: kind, name, intro, prompt, builtin?, createdAt, updatedAt.
public enum InterviewTypes {
    public struct Builtin: Decodable, Equatable, Identifiable {
        public let slug: String, nameKey: String, introKey: String, prompt: String
        public var id: String { slug }
    }
    public static let builtins: [Builtin] = {
        guard let url = Bundle.module.url(forResource: "builtin-interviews", withExtension: "json"), let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([Builtin].self, from: data) else { return [] }
        return list
    }()
    /// Seeds no synced record (live or tombstone) has forked yet.
    public static func pristine(records: [VaultRecord]) -> [Builtin] {
        let forked = Set(records.filter { $0.kind == "interviewType" }.compactMap { $0.body["builtin"]?.string })
        return builtins.filter { !forked.contains($0.slug) }
    }
    /// Web EditorView save: `name.trim() || untitled`, `intro.trim()`, `prompt.trim()`.
    public static func cleaned(name: String, intro: String, prompt: String, untitled: String) -> (name: String, intro: String, prompt: String) {
        let ws = EntryLinkAuthoring.ecmaWhitespace
        let n = name.trimmingCharacters(in: ws)
        return (n.isEmpty ? untitled : n, intro.trimmingCharacters(in: ws), prompt.trimmingCharacters(in: ws))
    }
    static func body(name: String, intro: String, prompt: String, builtin: String?, created: Double, updated: Double) -> [String: JSONValue] {
        var b: [String: JSONValue] = ["kind": .string("interviewType"), "name": .string(name), "intro": .string(intro), "prompt": .string(prompt), "createdAt": .number(created), "updatedAt": .number(updated)]
        if let builtin { b["builtin"] = .string(builtin) }
        return b
    }
    /// Web `createInterviewType`.
    public static func newType(name: String, intro: String, prompt: String, id: String, clock: Int64) throws -> VaultRecord {
        guard !id.isEmpty else { throw ChapterError.unsupported }
        try ProtocolNumbers.validate(clock)
        return VaultRecord(id: id, clock: clock, body: body(name: name, intro: intro, prompt: prompt, builtin: nil, created: Double(clock), updated: Double(clock)), dirty: true)
    }
    /// Web `mutateSeeded` on a pristine seed: the first edit or delete forks it into a
    /// synced record carrying the builtin slug (name and intro as currently shown).
    public static func fork(_ seed: Builtin, name: String, intro: String, prompt: String, id: String, clock: Int64, deleted: Bool = false) throws -> VaultRecord {
        guard !id.isEmpty else { throw ChapterError.unsupported }
        try ProtocolNumbers.validate(clock)
        return VaultRecord(id: id, clock: clock, deleted: deleted, body: body(name: name, intro: intro, prompt: prompt, builtin: seed.slug, created: Double(clock), updated: Double(clock)), dirty: true)
    }
}

public extension VaultRecord {
    /// Web `updateInterviewType(id, {name, intro, prompt})`: those fields and updatedAt
    /// change; builtin slug, createdAt and unknown fields are kept.
    func editingInterviewType(expected: VaultRecord, name: String, intro: String, prompt: String, now: Date = Date()) throws -> VaultRecord {
        guard kind == "interviewType", !deleted else { throw ChapterError.unsupported }
        try requiringUnchanged(expected: expected)
        var copy = self
        copy.body["name"] = .string(name); copy.body["intro"] = .string(intro); copy.body["prompt"] = .string(prompt)
        guard !copy.hasSamePayload(as: self) else { return self }
        copy.clock = try ProtocolNumbers.nextClock(after: clock, now: now)
        copy.body["updatedAt"] = .number(Double(copy.clock)); copy.dirty = true
        return copy
    }
    /// Web `deleteInterviewType`: a synced tombstone; every other field is retained.
    func deletingInterviewType(expected: VaultRecord, now: Date = Date()) throws -> VaultRecord {
        guard kind == "interviewType", !deleted else { throw ChapterError.unsupported }
        try requiringUnchanged(expected: expected)
        var copy = self; copy.deleted = true; copy.dirty = true
        copy.clock = try ProtocolNumbers.nextClock(after: clock, now: now)
        copy.body["updatedAt"] = .number(Double(copy.clock))
        return copy
    }
}
