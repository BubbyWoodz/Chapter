// SPDX-License-Identifier: AGPL-3.0-or-later
import XCTest
@testable import ChapterCore
#if canImport(CryptoKit)
import CryptoKit
#endif

final class MathRenderingTests: XCTestCase {
    private func fixture() throws -> JSONValue { try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: try XCTUnwrap(Bundle.module.url(forResource: "math-render", withExtension: "json")))) }

    func testOptionsAndBundledKaTeXEqualTheWebBuild() throws {
        let f = try fixture()
        guard case .object(let web) = f["options"] else { return XCTFail("options") }
        XCTAssertEqual(Set(web.keys), Set(ChapterMath.options.keys))
        XCTAssertEqual(web["throwOnError"], .bool(false)); XCTAssertEqual(ChapterMath.options["throwOnError"] as? Bool, false)
        XCTAssertEqual(web["trust"], .bool(false)); XCTAssertEqual(ChapterMath.options["trust"] as? Bool, false)
        XCTAssertEqual(web["strict"]?.string, ChapterMath.options["strict"] as? String)
        XCTAssertEqual(web["maxExpand"]?.number, (ChapterMath.options["maxExpand"] as? Int).map(Double.init))
        XCTAssertEqual(web["maxSize"]?.number, (ChapterMath.options["maxSize"] as? Int).map(Double.init))
        let dir = try XCTUnwrap(ChapterMath.resourceDirectory)
        let script = try Data(contentsOf: dir.appendingPathComponent("katex.min.js"))
        XCTAssertEqual(Data(SHA256.hash(data: script)).hex, f["scriptSHA256"].string, "Bundled KaTeX must be the web's exact build")
        for name in ["katex.min.css", "LICENSE", "fonts/KaTeX_Main-Regular.woff2", "fonts/KaTeX_Math-Italic.woff2"] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent(name).path), name)
        }
    }

    func testNativeKaTeXOutputEqualsWebRenderLatex() throws {
        #if canImport(JavaScriptCore)
        let cases = try fixture()["cases"].array
        XCTAssertEqual(cases.count, 16)
        let renderer = KaTeXRenderer()
        for c in cases {
            let latex = c["latex"].string ?? "", kind = MathKind(rawValue: c["kind"].string ?? "") ?? .inline
            XCTAssertEqual(renderer.html(latex, kind: kind), c["html"].string, latex)
        }
        XCTAssertEqual(renderer.html("x^2", kind: .inline), cases[0]["html"].string, "Cached result is identical")
        #else
        throw XCTSkip("JavaScriptCore is Apple-only; the bundle and options are still checked above")
        #endif
    }

    func testInlineHTMLEscapesTextAndAllowsOnlySafeLinks() throws {
        let block = try JSONDecoder().decode(JSONValue.self, from: Data(#"{"type":"paragraph","content":[{"type":"text","text":"a<b>&\"'","marks":[{"type":"bold"},{"type":"italic"}]},{"type":"inlineMath","attrs":{"latex":"x^2"}},{"type":"text","text":"go","marks":[{"type":"link","attrs":{"href":"https://example.invalid/?q=1&r=\"2\""}}]},{"type":"text","text":"bad","marks":[{"type":"link","attrs":{"href":"javascript:alert(1)"}}]},{"type":"hardBreak"},{"type":"entryLink","attrs":{"entryId":"e1","label":"Old <label>"}},{"type":"futureInline"}]}"#.utf8))
        XCTAssertTrue(RichMathHTML.containsInlineMath(block))
        let html = RichMathHTML.inline(block, entryLabel: { $0 == "e1" ? "New & title" : nil }, math: { latex, kind in kind == .inline && latex == "x^2" ? "<span class=\"katex\">K</span>" : nil })
        XCTAssertEqual(html, "<strong><em>a&lt;b&gt;&amp;&quot;&#39;</em></strong><span class=\"katex\">K</span><a href=\"https://example.invalid/?q=1&amp;r=%222%22\">go</a>bad<br><a href=\"chapter-entry://open?id=e1\">New &amp; title</a>[futureInline — preserved]")
        let fallback = RichMathHTML.inline(block, entryLabel: { _ in nil }, math: { _, _ in nil })
        XCTAssertTrue(fallback.contains("<code>x^2</code>")); XCTAssertTrue(fallback.contains("Old &lt;label&gt;"))
    }

    func testPageHasNoScriptAndBlocksNetwork() {
        let page = RichMathHTML.page(body: "<b>x</b>", fontFamily: "Newsreader16pt-Regular'};x{", fontSize: 1000, ink: "#112233", paper: "red;}", link: "#ABCDEF", block: false)
        XCTAssertFalse(page.lowercased().contains("<script"))
        XCTAssertTrue(page.contains("script-src 'none'")); XCTAssertTrue(page.contains("default-src 'none'")); XCTAssertTrue(page.contains("connect-src 'none'"))
        XCTAssertTrue(page.contains("font-family:'Newsreader16pt-Regularx'"), "Family is reduced to safe characters")
        XCTAssertTrue(page.contains("font-size:96.00px"), "Size is bounded")
        XCTAssertTrue(page.contains("background:#000000"), "A non-hex colour never reaches CSS")
        XCTAssertTrue(page.contains("color:#112233"))
    }
}
