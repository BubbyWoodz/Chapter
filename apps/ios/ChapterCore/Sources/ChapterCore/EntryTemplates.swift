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
}
