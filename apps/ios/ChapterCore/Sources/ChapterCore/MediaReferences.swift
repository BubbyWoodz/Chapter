// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

public struct VaultMedia: Identifiable, Equatable {
    public let id: String
    public let kind: String
    public let mime: String
    public let name: String
    public let bytes: Int
    init(id: String, kind: String, mime: String, name: String, bytes: Int) { self.id = id; self.kind = kind; self.mime = mime; self.name = name; self.bytes = bytes }
    public init?(_ raw: JSONValue, forceKind: String? = nil) {
        guard let id = raw["id"].string, !id.isEmpty else { return nil }
        let size = raw["bytes"].number ?? 0
        guard size.isFinite, let byteCount = Int(exactly: size), byteCount >= 0 else { return nil }
        self.id = id; self.kind = forceKind ?? raw["kind"].string ?? "video"
        self.mime = raw["mime"].string ?? "application/octet-stream"
        self.name = raw["name"].string ?? (forceKind ?? raw["kind"].string ?? "Recording")
        self.bytes = byteCount
    }
}
public extension VaultRecord {
    // Match web export/collect.ts: arrays, gallery, map, interviews and legacy attachments.
    var mediaReferences: [VaultMedia] {
        var result: [VaultMedia] = []
        var seen = Set<String>()
        func add(_ raw: JSONValue, kind: String? = nil) {
            if let media = VaultMedia(raw, forceKind: kind), seen.insert(media.id).inserted { result.append(media) }
        }
        func walk(_ node: JSONValue) {
            let attrs = node["attrs"]
            switch node["type"].string {
            case "mediaAttachment": add(attrs)
            case "mediaGallery": attrs["images"].array.forEach { add($0, kind: "image") }
            case "locationMap": add(attrs["map"], kind: "image"); add(attrs["photo"], kind: "image")
            case "videoInterview": attrs["cards"].array.forEach { add($0["clip"]) }; add(attrs["film"])
            default: break
            }
            node["content"].array.forEach(walk)
        }
        if let source = body["bodyJson"]?.string, let doc = try? JSONDecoder().decode(JSONValue.self, from: Data(source.utf8)) { walk(doc) }
        body["attachments"]?.array.forEach { add($0) }
        return result
    }
}
