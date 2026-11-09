// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

/// Display labels for original custom nodes, mirroring web DocPreview.tsx
/// (`typeof x === 'string' && x` truthiness, English catalog strings).
public enum RichCustomBlockLabel {
    static func nonEmpty(_ value: JSONValue) -> String? { if let s = value.string, !s.isEmpty { return s }; return nil }
    public static func location(_ attrs: JSONValue) -> String {
        let from = nonEmpty(attrs["from"]["label"]) ?? "Location"
        if let to = nonEmpty(attrs["to"]["label"]) { return "📍 " + from + " → " + to }
        return "📍 " + from
    }
    public static func videoInterview(_ attrs: JSONValue) -> String {
        let name = nonEmpty(attrs["typeName"]) ?? "Video interview"
        let count: Int; if case .array(let cards) = attrs["cards"] { count = cards.count } else { count = 0 }
        return "🎬 " + name + (count > 0 ? " · " + (count == 1 ? "1 question" : "\(count) questions") : "")
    }
}
