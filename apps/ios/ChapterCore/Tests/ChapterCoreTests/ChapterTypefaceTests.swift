// SPDX-License-Identifier: AGPL-3.0-or-later
import XCTest
@testable import ChapterCore
final class ChapterTypefaceTests: XCTestCase {
    func testActualOriginalSkinTypographyRolesAndItalicCompanions() {
        for skin in SharedAppearance.skins {
            XCTAssertEqual(ChapterTypeface.postscript(.ui,skin:skin),"HankenGrotesk-Regular")
            XCTAssertEqual(ChapterTypeface.postscript(.mono,skin:skin),"SplineSansMono-Regular")
            XCTAssertEqual(ChapterTypeface.postscript(.heading,skin:skin),["modern","terminal"].contains(skin) ? "HankenGrotesk-Regular":"Newsreader16pt-Regular")
            XCTAssertEqual(ChapterTypeface.postscript(.prose,skin:skin),skin == "terminal" ? "HankenGrotesk-Regular":"Newsreader16pt-Regular")
            for role in ChapterFontRole.allCases { XCTAssertTrue(ChapterTypeface.postscript(role,skin:skin,italic:true).hasSuffix("-Italic")) }
        }
    }
}
