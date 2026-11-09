// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

/// One original web language (i18n LOCALES): endonym, English name, direction.
public struct ChapterLocale: Codable, Equatable, Hashable, Identifiable {
    public let id: String
    public let name: String
    public let english: String
    public let dir: String
    public var isRightToLeft: Bool { dir == "rtl" }
}

/// The original web's languages and every built-in template seed in each,
/// generated through the web's own setLocale + seedBuiltinTemplates
/// (apps/client/scripts/native-locale-vectors.ts, re-verified on every CI run).
public struct LocalizedBuiltins: Codable, Equatable {
    public let locales: [ChapterLocale]
    public let seeds: [String: [BuiltinTemplate]]
}

public enum ChapterLocales {
    public static func load(from data: Data) throws -> LocalizedBuiltins {
        let value = try JSONDecoder().decode(LocalizedBuiltins.self, from: data)
        guard value.locales.first?.id == "en", Set(value.locales.map(\.id)).count == value.locales.count,
              value.locales.allSatisfy({ ["ltr", "rtl"].contains($0.dir) && !$0.name.isEmpty }),
              let english = value.seeds["en"], !english.isEmpty, Set(value.seeds.keys) == Set(value.locales.map(\.id)),
              value.seeds.values.allSatisfy({ $0.map(\.slug) == english.map(\.slug) }) else { throw ChapterError.corruptData }
        return value
    }
    public static let bundled: LocalizedBuiltins? = {
        #if SWIFT_PACKAGE
        guard let url = Bundle.module.url(forResource: "builtin-templates-locales", withExtension: "json"), let data = try? Data(contentsOf: url) else { return nil }
        return try? load(from: data)
        #else
        return nil
        #endif
    }()
    /// Original initI18n: a stored, known language; anything else is English.
    /// The choice is device-local like the web's localStorage and never syncs.
    public static func resolve(stored: String?, in catalog: LocalizedBuiltins) -> ChapterLocale {
        catalog.locales.first { $0.id == stored } ?? catalog.locales[0]
    }
    /// Built-in seeds as the web shows pristine ones (localizeBuiltinTemplate):
    /// in the active language; the first rename or delete forks the shown text.
    public static func seeds(for locale: String, in catalog: LocalizedBuiltins) -> [BuiltinTemplate] {
        catalog.seeds[resolve(stored: locale, in: catalog).id] ?? catalog.seeds["en"] ?? []
    }
}
