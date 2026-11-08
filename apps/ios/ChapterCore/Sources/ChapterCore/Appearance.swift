// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

public struct SharedAppearance: Codable, Equatable {
    public var v = 1
    public var mode: String
    public var palette: String
    public var skin: String
    public static let modes = ["light", "dark", "system"]
    public static let palettes = ["terracotta", "moss", "sea", "twilight", "plum", "rose"]
    public static let skins = ["paper", "modern", "terminal", "forest", "blossom", "lavender"]
    public init(mode: String = "system", palette: String = "terracotta", skin: String = "paper") throws {
        guard Self.modes.contains(mode), Self.palettes.contains(palette), Self.skins.contains(skin) else { throw ChapterError.unsupported }
        self.mode=mode; self.palette=palette; self.skin=skin
    }
    public init(value: JSONValue) throws {
        guard value["v"] == .number(1), let mode=value["mode"].string, let palette=value["palette"].string, let skin=value["skin"].string else { throw ChapterError.unsupported }
        try self.init(mode:mode,palette:palette,skin:skin)
    }
    public var value: JSONValue { .object(["v":.number(1),"mode":.string(mode),"palette":.string(palette),"skin":.string(skin)]) }
    public static var standard: SharedAppearance { try! SharedAppearance() } // literal validated constants only
}
public enum AppearanceCatalog {
    public static let value: JSONValue = {
        guard let url=Bundle.module.url(forResource:"appearance-v1",withExtension:"json"), let data=try? Data(contentsOf:url),let json=try? JSONDecoder().decode(JSONValue.self,from:data) else { return .null }
        return json
    }()
    public static func tokens(_ preference: SharedAppearance, dark: Bool) -> JSONValue { value["skins"][preference.skin][dark ? "dark":"light"] }
}
extension VaultSnapshot {
    public var appearanceRecord: VaultRecord? {
        records.filter{$0.kind=="aiSettings"}.sorted { $0.clock == $1.clock ? $0.id < $1.id : $0.clock > $1.clock }.first
    }
    public var appearance: SharedAppearance? {
        guard let row=appearanceRecord,!row.deleted else { return nil }
        return try? SharedAppearance(value:row.body["settings"]?["chapterAppearance"] ?? .null)
    }
    public mutating func setAppearance(_ preference: SharedAppearance, now: Date = Date()) throws {
        _ = try SharedAppearance(value:preference.value)
        let previous=appearanceRecord
        var body = previous?.deleted == false ? (previous?.body ?? [:]) : [:]
        let settingsValue = body["settings"] ?? AppearanceCatalog.value["defaultSettings"]
        guard case .object(var settings)=settingsValue else { throw ChapterError.unsupported }
        if let unknown=settings["chapterAppearance"], unknown != .null { _=try SharedAppearance(value:unknown) }
        var appearanceFields: [String:JSONValue] = [:]
        if case .object(let original) = settings["chapterAppearance"] { appearanceFields=original }
        if case .object(let changes) = preference.value { appearanceFields.merge(changes,uniquingKeysWith: { _, new in new }) }
        settings["chapterAppearance"] = .object(appearanceFields)
        body["kind"] = .string("aiSettings");body["settings"] = .object(settings)
        let clock=try ProtocolNumbers.nextClock(after:previous?.clock ?? 0,now:now)
        body["updatedAt"] = .number(Double(clock))
        let id=records.filter{$0.kind=="aiSettings"}.map(\.id).min() ?? UUID().uuidString.replacingOccurrences(of:"-",with:"").lowercased()
        let row=VaultRecord(id:id,clock:clock,body:body,dirty:true)
        if let i=records.firstIndex(where:{$0.id==id}) { records[i]=row } else { records.append(row) }
    }
}
