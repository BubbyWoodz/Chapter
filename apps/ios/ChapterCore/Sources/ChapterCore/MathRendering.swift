import Foundation
#if canImport(JavaScriptCore)
import JavaScriptCore
#endif

public enum MathKind: String, Codable { case inline, block }

/// The web's math typesetting, natively: the exact KaTeX build the web ships
/// (bundled byte-for-byte, checked by native-math-vectors.ts) with the web's
/// own KATEX_OPTIONS. `trust: false` keeps \href, \url, \includegraphics and
/// \html* inert; maxExpand/maxSize bound the work one formula can cost.
public enum ChapterMath {
    /// Exactly the web's KATEX_OPTIONS (apps/client/src/editor/math.tsx).
    public static let options: [String: Any] = ["throwOnError": false, "trust": false, "strict": "ignore", "maxExpand": 1000, "maxSize": 500]
    /// The bundled KaTeX directory (katex.min.js, katex.min.css, fonts/, LICENSE).
    public static var resourceDirectory: URL? {
        #if SWIFT_PACKAGE
        return Bundle.module.url(forResource: "KaTeX", withExtension: nil)
        #else
        return nil
        #endif
    }
}

#if canImport(JavaScriptCore)
/// Runs KaTeX.renderToString in an isolated JavaScriptCore context. JavaScriptCore
/// has no DOM, network or file access; the result is static HTML (no script).
public final class KaTeXRenderer {
    public static let shared = KaTeXRenderer()
    private let lock = NSLock()
    private var context: JSContext?
    private var failed = false
    private var cache: [String: String] = [:]
    public init() {}

    /// Web renderLatex(latex, kind). nil only if KaTeX itself is unavailable or
    /// throws a non-parse error, where the web shows its error state instead.
    public func html(_ latex: String, kind: MathKind) -> String? {
        lock.lock(); defer { lock.unlock() }
        let key = kind.rawValue + "\u{0}" + latex
        if let hit = cache[key] { return hit }
        guard let context = loadedContext() else { return nil }
        var threw = false
        context.exceptionHandler = { _, _ in threw = true }
        var options = ChapterMath.options; options["displayMode"] = kind == .block
        let result = context.objectForKeyedSubscript("katex")?.invokeMethod("renderToString", withArguments: [latex, options])
        guard !threw, let result, result.isString, let html = result.toString() else { return nil }
        if cache.count > 512 { cache.removeAll() }
        cache[key] = html; return html
    }
    private func loadedContext() -> JSContext? {
        if let context { return context }
        guard !failed, let dir = ChapterMath.resourceDirectory,
              let script = try? String(contentsOf: dir.appendingPathComponent("katex.min.js"), encoding: .utf8),
              let made = JSContext() else { failed = true; return nil }
        var threw = false
        made.exceptionHandler = { _, _ in threw = true }
        // KaTeX logs unsupported-glyph warnings through console; keep them silent.
        made.evaluateScript("var console = { warn: function(){}, log: function(){}, error: function(){} };")
        made.evaluateScript(script)
        guard !threw, made.objectForKeyedSubscript("katex")?.isObject == true else { failed = true; return nil }
        context = made; return made
    }
}
#endif

/// Static HTML for a paragraph or heading that contains inline math, so the
/// formula sits in the line exactly as the web lays it out. Text is escaped;
/// only https/http/mailto links and local entry links become anchors (the app
/// routes every activation through its own confirmation/navigation).
public enum RichMathHTML {
    public static func escape(_ text: String) -> String {
        var out = ""; out.reserveCapacity(text.utf8.count)
        for c in text.unicodeScalars {
            switch c {
            case "&": out += "&amp;"; case "<": out += "&lt;"; case ">": out += "&gt;"
            case "\"": out += "&quot;"; case "'": out += "&#39;"
            default: out.unicodeScalars.append(c)
            }
        }
        return out
    }
    public static func containsInlineMath(_ block: JSONValue) -> Bool { block["content"].array.contains { $0["type"].string == "inlineMath" } }

    /// - Parameters:
    ///   - entryLabel: the current title for a linked entry id (or nil to use the stored label).
    ///   - math: KaTeX HTML for (latex, kind); nil shows the escaped LaTeX source.
    public static func inline(_ block: JSONValue, entryLabel: (String) -> String?, math: (String, MathKind) -> String?) -> String {
        block["content"].array.map { node -> String in
            switch node["type"].string ?? "" {
            case "text":
                var html = escape(node["text"].string ?? "")
                // Innermost first, so the stored order nests outward like ProseMirror's DOM.
                for mark in node["marks"].array.reversed() {
                    switch mark["type"].string ?? "" {
                    case "bold": html = "<strong>" + html + "</strong>"
                    case "italic": html = "<em>" + html + "</em>"
                    case "underline": html = "<u>" + html + "</u>"
                    case "strike": html = "<s>" + html + "</s>"
                    case "code": html = "<code>" + html + "</code>"
                    case "link":
                        if let raw = mark["attrs"]["href"].string, let url = URL(string: raw), ["https", "http", "mailto"].contains(url.scheme?.lowercased() ?? "") {
                            html = "<a href=\"" + escape(url.absoluteString) + "\">" + html + "</a>"
                        }
                    default: break
                    }
                }
                return html
            case "hardBreak": return "<br>"
            case "inlineMath":
                let latex = node["attrs"]["latex"].string ?? ""
                return math(latex, .inline) ?? "<code>" + escape(latex) + "</code>"
            case "entryLink":
                let id = node["attrs"]["entryId"].string ?? ""
                let label = escape(entryLabel(id) ?? node["attrs"]["label"].string ?? "Related entry")
                guard let url = EntryLinkRoute.url(for: id) else { return label }
                return "<a href=\"" + escape(url.absoluteString) + "\">" + label + "</a>"
            case let other: return escape("[\(other) — preserved]")
            }
        }.joined()
    }

    /// A complete document: no script, a CSP that allows only bundled files and
    /// inline styles, KaTeX's stylesheet, and the caller's theme.
    public static func page(body: String, fontFamily: String, fontSize: Double, ink: String, paper: String, link: String, block: Bool, heading: Bool = false) -> String {
        let safeFamily = fontFamily.filter { $0.isLetter || $0.isNumber || $0 == " " || $0 == "-" }
        func hex(_ value: String) -> String { value.range(of: "^#[0-9A-Fa-f]{6}$", options: .regularExpression) != nil ? value : "#000000" }
        return """
        <!doctype html><html><head><meta charset="utf-8">\
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'self' file: 'unsafe-inline'; font-src 'self' file:; img-src 'none'; script-src 'none'; connect-src 'none'; frame-src 'none'">\
        <meta name="viewport" content="width=device-width, initial-scale=1">\
        <link rel="stylesheet" href="katex.min.css">\
        <style>html,body{margin:0;padding:0;background:\(hex(paper));color:\(hex(ink));-webkit-text-size-adjust:none}\
        body{font-family:'\(safeFamily)',Georgia,serif;font-size:\(String(format: "%.2f", max(8, min(fontSize, 96))))px;line-height:1.5;\(heading ? "font-weight:600;" : "")overflow-wrap:anywhere}\
        a{color:\(hex(link))}code{font-family:'SplineSansMono-Regular',ui-monospace,monospace;font-size:.9em}\
        .katex-display{margin:.25em 0;overflow-x:auto;overflow-y:hidden}</style></head>\
        <body>\(block ? body : "<p style=\"margin:0\">" + body + "</p>")</body></html>
        """
    }
}
