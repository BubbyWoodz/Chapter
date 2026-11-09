// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

/// Mirrors the original web "Use template" (app.tsx newEntryFromTemplate +
/// state/data.tsx createEntry): a new entry whose bodyJson/bodyText are the
/// template's EXACT stored strings, title = defaultEntryTitle(now), no labels.
public enum EntryTemplates {
    /// Web TemplatesSheet/NewJournalSheet label: `name || t('journals.untitledTemplate')`.
    public static func name(_ template: VaultRecord) -> String {
        if let value = template.body["name"]?.string, !value.isEmpty { return value }
        return "Untitled template"
    }
    /// Original `defaultEntryTitle`: local `YYYY-MM-DD HH:MM:SS`.
    public static func defaultTitle(milliseconds: Double, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
        let date = Date(timeIntervalSince1970: milliseconds / 1000)
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        func p(_ v: Int?) -> String { let n = v ?? 0; return n < 10 ? "0\(n)" : "\(n)" }
        return "\(c.year ?? 0)-\(p(c.month))-\(p(c.day)) \(p(c.hour)):\(p(c.minute)):\(p(c.second))"
    }
    public static func newEntry(from template: VaultRecord, journalID: String, id: String, clock: Int64, timeZone: TimeZone = .current) throws -> VaultRecord {
        guard template.kind == "template", !template.deleted, !journalID.isEmpty, !id.isEmpty else { throw ChapterError.unsupported }
        if let raw = template.body["bodyJson"], raw.string == nil, raw != .null { throw ChapterError.unsupported }
        if let raw = template.body["bodyText"], raw.string == nil, raw != .null { throw ChapterError.unsupported }
        let now = Double(clock)
        var body: [String: JSONValue] = [
            "journalId": .string(journalID), "title": .string(defaultTitle(milliseconds: now, timeZone: timeZone)),
            "bodyText": .string(template.body["bodyText"]?.string ?? ""), "labels": .array([]),
            "createdAt": .number(now), "updatedAt": .number(now),
        ]
        // Web passes bodyJson through untouched (undefined stays absent).
        if let json = template.body["bodyJson"]?.string { body["bodyJson"] = .string(json) }
        return VaultRecord(id: id, clock: clock, body: body, dirty: true)
    }
    /// Web TemplateEditorView save: `name.trim() || t('templates.untitled')`.
    public static func savedName(_ input: String) -> String {
        let value = input.trimmingCharacters(in: EntryLinkAuthoring.ecmaWhitespace)
        return value.isEmpty ? "Untitled template" : value
    }
    /// Original web `createTemplate`: kind/name/bodyText/bodyJson/createdAt/updatedAt.
    /// An untouched body keeps bodyJson absent and bodyText "" (web `json || undefined`).
    /// Native body authoring is plain paragraphs; rich template bodies stay web-authored.
    public static func newTemplate(name: String, text: String, id: String, clock: Int64) throws -> VaultRecord {
        guard !id.isEmpty, text.utf8.count <= 1_000_000 else { throw ChapterError.unsupported }
        try ProtocolNumbers.validate(clock)
        let now = Double(clock)
        var body: [String: JSONValue] = ["kind": .string("template"), "name": .string(savedName(name)), "bodyText": .string(""), "createdAt": .number(now), "updatedAt": .number(now)]
        if !text.isEmpty {
            let json = try VaultRecord.plainDocument(text)
            body["bodyJson"] = .string(json); body["bodyText"] = .string(try RichDocument(json: json).plainText)
        }
        return VaultRecord(id: id, clock: clock, body: body, dirty: true)
    }
}

public extension VaultRecord {
    /// Web `updateTemplate(id,{name})` through mutateSeeded: only the name and
    /// updatedAt change; body bytes, builtin slug and unknown fields are kept.
    func renamingTemplate(expected: VaultRecord, name: String, now: Date = Date()) throws -> VaultRecord {
        guard kind == "template", !deleted else { throw ChapterError.unsupported }
        try requiringUnchanged(expected: expected)
        var copy = self; copy.body["name"] = .string(EntryTemplates.savedName(name))
        guard !copy.hasSamePayload(as: self) else { return self }
        copy.clock = try ProtocolNumbers.nextClock(after: clock, now: now)
        copy.body["updatedAt"] = .number(Double(copy.clock)); copy.dirty = true
        return copy
    }
    /// Web `deleteTemplate`: a synced tombstone (built-ins included) so the
    /// deletion reaches other devices; every other field is retained.
    func deletingTemplate(expected: VaultRecord, now: Date = Date()) throws -> VaultRecord {
        guard kind == "template", !deleted else { throw ChapterError.unsupported }
        try requiringUnchanged(expected: expected)
        var copy = self; copy.deleted = true; copy.dirty = true
        copy.clock = try ProtocolNumbers.nextClock(after: clock, now: now)
        copy.body["updatedAt"] = .number(Double(copy.clock))
        return copy
    }
}
