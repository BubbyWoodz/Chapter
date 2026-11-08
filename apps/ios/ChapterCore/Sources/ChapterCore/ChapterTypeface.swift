// SPDX-License-Identifier: AGPL-3.0-or-later
/// Original apps/client/src/styles/tokens.css roles. Native controls retain native
/// layout; custom fonts must use Font.custom(...relativeTo:) for Dynamic Type.
public enum ChapterFontRole: CaseIterable { case ui, heading, prose, mono }
public enum ChapterTypeface {
    public static func postscript(_ role: ChapterFontRole, skin: String, italic: Bool = false) -> String {
        let sans = role == .ui || (role == .heading && ["modern","terminal"].contains(skin)) || (role == .prose && skin == "terminal")
        if role == .mono { return "SplineSansMono-" + (italic ? "Italic":"Regular") }
        if sans { return "HankenGrotesk-" + (italic ? "Italic":"Regular") }
        return "Newsreader16pt-" + (italic ? "Italic":"Regular")
    }
}
