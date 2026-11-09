// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

/// Port of the web's state/badges.ts: awards derived from the decrypted entries each
/// session (nothing synced), plus the device-local "already celebrated" set and the
/// quiet first-run catch-up.
public enum ChapterBadges {
    public struct Entry: Equatable {
        public let id: String, deleted: Bool, createdAt: Double, bodyText: String, bodyJson: String?, labels: [String], attachments: Int
        public init(id: String, deleted: Bool = false, createdAt: Double, bodyText: String, bodyJson: String? = nil, labels: [String] = [], attachments: Int = 0) {
            self.id = id; self.deleted = deleted; self.createdAt = createdAt; self.bodyText = bodyText; self.bodyJson = bodyJson; self.labels = labels; self.attachments = attachments
        }
    }
    public struct BuiltinInterview: Decodable, Equatable { public let slug: String; public let nameKey: String }
    struct Data_: Decodable { let order: [String]; let seedEntryIds: [String]; let interviews: [BuiltinInterview] }
    static let data: Data_ = {
        guard let url = Bundle.module.url(forResource: "badges", withExtension: "json"), let raw = try? Data(contentsOf: url),
              let value = try? JSONDecoder().decode(Data_.self, from: raw) else { return Data_(order: [], seedEntryIds: [], interviews: []) }
        return value
    }()
    /// Fixed gallery and celebration order.
    public static var order: [String] { data.order }
    public static var seedEntryIDs: Set<String> { Set(data.seedEntryIds) }
    public static var builtinInterviews: [BuiltinInterview] { data.interviews }

    public static func entries(_ records: [VaultRecord]) -> [Entry] {
        records.map { r in
            Entry(id: r.id, deleted: r.deleted, createdAt: r.body["createdAt"]?.number ?? Double(r.clock), bodyText: r.body["bodyText"]?.string ?? "",
                  bodyJson: r.body["bodyJson"]?.string, labels: r.body["labels"]?.array.compactMap { $0.string } ?? [], attachments: r.body["attachments"]?.array.count ?? 0)
        }
    }
    /// Live interview-type names: synced, non-deleted records plus the built-in seeds no
    /// synced record has forked (named in the current language, like the web projection).
    public static func interviewTypeNames(_ records: [VaultRecord], name: (String) -> String) -> [String] {
        let types = records.filter { $0.kind == "interviewType" }
        let forked = Set(types.compactMap { $0.body["builtin"]?.string })
        return builtinInterviews.filter { !forked.contains($0.slug) }.map { name($0.nameKey) } + types.filter { !$0.deleted }.compactMap { $0.body["name"]?.string }
    }

    static func hasNode(_ node: JSONValue, _ type: String) -> Bool {
        if node["type"].string == type { return true }
        return node["content"].array.contains { hasNode($0, type) }
    }
    /// editor/doc `docMediaIds` (ids only: any non-empty string id).
    static func mediaIDs(_ doc: JSONValue) -> [String] {
        var ids: [String] = []
        func push(_ v: JSONValue) { if let id = v["id"].string, !id.isEmpty { ids.append(id) } }
        func walk(_ n: JSONValue) {
            let attrs = n["attrs"]
            switch n["type"].string {
            case "mediaAttachment": push(attrs)
            case "mediaGallery": attrs["images"].array.forEach(push)
            case "locationMap": push(attrs["map"]); push(attrs["photo"])
            case "videoInterview": if case .object = attrs { attrs["cards"].array.forEach { push($0["clip"]) }; push(attrs["film"]) }
            default: break
            }
            n["content"].array.forEach(walk)
        }
        walk(doc); return ids
    }
    /// `parseBody`: JSON when it parses, else the plain-text doc (which holds no nodes of interest).
    static func parse(_ json: String) -> JSONValue? { try? JSONDecoder().decode(JSONValue.self, from: Data(json.utf8)) }

    public static func evaluate(_ entries: [Entry], interviewTypeNames: [String]) -> Set<String> {
        let user = entries.filter { !$0.deleted && !seedEntryIDs.contains($0.id) }
        var earned = Set<String>()
        if !user.isEmpty { earned.insert("first-words") }
        let items = user.map { ChapterStats.Item(id: $0.id, createdAt: $0.createdAt, bodyText: $0.bodyText) }
        let streak = ChapterStats.longestStreak(items)
        if streak >= 3 { earned.insert("streak-3") }
        if streak >= 7 { earned.insert("streak-7") }
        if ChapterStats.totalWords(items) >= 1000 { earned.insert("wordsmith") }
        if user.contains(where: { ChapterStats.wordCount($0.bodyText) >= 1000 }) { earned.insert("deep-dive") }
        let names = Set(interviewTypeNames)
        if user.contains(where: { $0.labels.contains(where: names.contains) }) { earned.insert("first-interview") }
        if user.contains(where: { e in
            guard let json = e.bodyJson, json.contains("\"videoInterview\""), let doc = parse(json) else { return false }
            return hasNode(doc, "videoInterview")
        }) { earned.insert("on-camera") }
        let mediaNodes = ["\"mediaAttachment\"", "\"mediaGallery\"", "\"locationMap\"", "\"videoInterview\""]
        if user.contains(where: { e in
            if e.attachments > 0 { return true }
            guard let json = e.bodyJson, !json.isEmpty, mediaNodes.contains(where: json.contains), let doc = parse(json) else { return false }
            return !mediaIDs(doc).isEmpty
        }) { earned.insert("memory-keeper") }
        return earned
    }

    public static func seenKey(_ ownerID: String) -> String { "mneme.badges.seen.\(ownerID)" }
    /// `loadSeen`: nil means never initialised here (absent, corrupt or not an array).
    public static func loadSeen(_ raw: String?) -> Set<String>? {
        guard let raw, let value = parse(raw), case .array(let items) = value else { return nil }
        return Set(items.compactMap { $0.string }.filter(order.contains))
    }
    /// `saveSeen` payload: the seen ids in badge order.
    public static func encodeSeen(_ seen: Set<String>) -> String {
        "[" + order.filter(seen.contains).map { "\"\($0)\"" }.joined(separator: ",") + "]"
    }
    /// `catchUpOrDelta`: first evaluation adopts everything quietly; afterwards newly
    /// earned badges celebrate in fixed order.
    public static func catchUpOrDelta(seen: Set<String>?, earned: Set<String>) -> (seen: Set<String>, celebrate: [String]) {
        guard let seen else { return (earned, []) }
        return (seen, order.filter { earned.contains($0) && !seen.contains($0) })
    }
}
