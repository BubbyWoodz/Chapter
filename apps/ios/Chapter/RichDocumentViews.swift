// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI
import ChapterCore

struct RichDocumentView: View {
    @EnvironmentObject private var model: VaultModel
    let entry: VaultRecord
    let document: RichDocument
    @State private var error: String?
    @State private var externalURL: URL?
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            render(document.node)
            Text("Native rich preview: math is shown as LaTeX; merged-table layout and custom media/interview cards are simplified. Unknown nodes and formatting remain intact.").font(.footnote).foregroundStyle(.secondary)
        }
        .environment(\.openURL, OpenURLAction { url in
            guard ["https", "http", "mailto"].contains(url.scheme?.lowercased() ?? "") else { return .discarded }
            externalURL = url; return .handled
        })
        .confirmationDialog("Open outside Chapter?", isPresented: Binding(get: { externalURL != nil }, set: { if !$0 { externalURL = nil } }), titleVisibility: .visible) {
            if let url = externalURL { Button("Open link") { UIApplication.shared.open(url); externalURL = nil } }
            Button("Cancel", role: .cancel) { externalURL = nil }
        } message: { Text(externalURL?.absoluteString ?? "") }
        .alert("Could not save task", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK", role: .cancel) {} } message: { Text(error ?? "") }
    }
    private func children(_ node: RichNode) -> some View {
        VStack(alignment: .leading, spacing: 10) { ForEach(node.children) { render($0) } }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func inline(_ node: RichNode, font: Font = .body) -> AttributedString {
        if node.type == "text" {
            var value = AttributedString(node.text), face = font
            for mark in node.value["marks"].array {
                switch mark["type"].string {
                case "bold": face = face.bold()
                case "italic": face = face.italic()
                case "code": face = face.monospaced()
                case "underline": value.underlineStyle = .single
                case "strike": value.strikethroughStyle = .single
                case "link":
                    if let raw = mark["attrs"]["href"].string, let url = URL(string: raw), ["https", "http", "mailto"].contains(url.scheme?.lowercased() ?? "") { value.link = url }
                default: break // Preserved in JSON, not stripped on edit.
                }
            }
            value.font = face; return value
        }
        if node.type == "hardBreak" { return AttributedString("\n") }
        if node.type == "inlineMath" { return AttributedString("⟨" + (node.value["attrs"]["latex"].string ?? "") + "⟩") }
        if node.type == "entryLink" { return AttributedString("🔗 " + (node.value["attrs"]["label"].string ?? "Related entry")) }
        if !["paragraph", "heading"].contains(node.type) { return AttributedString("[\(node.type) — preserved]") }
        return node.children.reduce(into: AttributedString()) { $0 += inline($1, font: font) }
    }
    private func render(_ node: RichNode) -> AnyView {
        switch node.type {
        case "doc", "listItem", "taskList": return AnyView(children(node))
        case "paragraph", "heading":
            let level = node.value["attrs"]["level"].number ?? 2
            let font: Font = node.type == "heading" ? (level == 1 ? .title : level == 2 ? .title2 : .title3) : .body
            let content = inline(node, font: font)
            return AnyView(Text(content.characters.isEmpty ? AttributedString(" ") : content).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).accessibilityAddTraits(node.type == "heading" ? .isHeader : []))
        case "bulletList", "orderedList":
            let raw = node.value["attrs"]["start"].number ?? 1
            let start = raw >= 0 && raw <= 1_000_000 ? (Int(exactly: raw) ?? 1) : 1
            return AnyView(VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(node.children.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .top) { Text(node.type == "bulletList" ? "•" : "\(start + index)."); children(item) }
                }
            })
        case "taskItem":
            let checked = node.value["attrs"]["checked"] == .bool(true)
            return AnyView(HStack(alignment: .top) {
                Button {
                    do { try model.toggleRichTask(entry, path: node.path) } catch { self.error = error.localizedDescription }
                } label: { Image(systemName: checked ? "checkmark.square.fill" : "square").padding(10) }
                    .accessibilityLabel(checked ? "Mark task incomplete" : "Mark task complete")
                children(node)
            })
        case "blockquote": return AnyView(HStack(alignment: .top) { Rectangle().fill(Color.secondary).frame(width: 3); children(node) }.fixedSize(horizontal: false, vertical: true).padding(.leading, 6))
        case "codeBlock": return AnyView(ScrollView(.horizontal) { Text(node.children.map(\.text).joined()).font(.body.monospaced()).textSelection(.enabled) }.padding().background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8)))
        case "horizontalRule": return AnyView(Divider().accessibilityLabel("Separator"))
        case "table": return AnyView(ScrollView(.horizontal) { children(node) }.accessibilityLabel("Table; merged cell layout is simplified"))
        case "tableRow": return AnyView(HStack(alignment: .top, spacing: 0) { ForEach(node.children) { render($0).frame(minWidth: 140, alignment: .leading) } })
        case "tableCell", "tableHeader": return AnyView(children(node).padding(10).background(Color(uiColor: .secondarySystemBackground)).border(Color.secondary.opacity(0.4)))
        case "blockMath": return AnyView(Text(node.value["attrs"]["latex"].string ?? "").font(.body.monospaced()).textSelection(.enabled).accessibilityLabel("LaTeX formula: " + (node.value["attrs"]["latex"].string ?? "")))
        case "mediaAttachment", "mediaGallery": return AnyView(Label(node.value["attrs"]["name"].string ?? "Encrypted media — use attachment preview below", systemImage: "paperclip").foregroundStyle(.secondary))
        case "locationMap": return AnyView(Label((node.value["attrs"]["from"]["label"].string ?? "Location") + " → " + (node.value["attrs"]["to"]["label"].string ?? ""), systemImage: "map").textSelection(.enabled))
        case "videoInterview": return AnyView(VStack(alignment: .leading) {
            Label(node.value["attrs"]["typeName"].string ?? "Video interview", systemImage: "video")
            ForEach(Array(node.value["attrs"]["cards"].array.enumerated()), id: \.offset) { _, card in
                Text(card["q"].string ?? "").font(.headline); Text(card["transcript"].string ?? "")
            }
        })
        default: return AnyView(Text("Unsupported \(node.type) node — preserved unchanged").font(.footnote).foregroundStyle(.secondary))
        }
    }
}

struct RichEntryEditor: View {
    @EnvironmentObject private var model: VaultModel
    let entry: VaultRecord
    let document: RichDocument
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section { Text("Edit individual formatted text runs. Marks, tables, media and unknown content are retained. Structural changes and a full formatting toolbar are not yet available.") }
                Section("Formatted text") {
                    ForEach(document.textLeaves) { leaf in
                        let draft = model.snapshot.richDrafts?.first { $0.entryID == entry.id && $0.path == leaf.path }
                            ?? RichDraft(entryID: entry.id, path: leaf.path, expectedDocument: entry.body["bodyJson"]?.string ?? "", text: leaf.text)
                        NavigationLink { RichDraftEditor(draft: draft) } label: { Text(leaf.text).lineLimit(3) }
                    }
                }
            }.navigationTitle("Edit rich entry").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }
    }
}

struct RichDraftEditor: View {
    @EnvironmentObject private var model: VaultModel
    @Environment(\.dismiss) private var dismiss
    let draft: RichDraft
    @State private var text: String
    @State private var error: String?
    @State private var savedDraft: Bool
    init(draft: RichDraft) {
        self.draft = draft; _text = State(initialValue: draft.text); _savedDraft = State(initialValue: false)
    }
    private var current: RichDraft { var value = draft; value.text = text; return value }
    var body: some View {
        VStack(alignment: .leading) {
            TextEditor(text: $text).accessibilityLabel("Formatted text run").autocorrectionDisabled().padding()
            Text(error ?? (savedDraft ? "Draft saved encrypted on this device. Tap Save to update the entry." : "Edit this run without removing its formatting. Any saved draft remains available in Settings after locking.")).font(.footnote).padding()
        }.navigationTitle("Edit text")
        .toolbar { Button("Save") {
            do { try model.applyRichDraft(current); dismiss() } catch { self.error = error.localizedDescription }
        } }
        .onChange(of: text) { _, _ in
            do { try model.saveRichDraft(current); savedDraft = true; error = nil } catch { self.error = error.localizedDescription }
        }
        .interactiveDismissDisabled(error != nil)
    }
}

#if DEBUG
// Public fixture only; never a way to unlock a real vault or bypass Keychain.
enum PublicRichFixture { static let json = #"{"type":"doc","futureRoot":{"keep":["all",1,true]},"content":[{"type":"heading","attrs":{"level":2,"future":"keep"},"content":[{"type":"text","text":"Public heading","marks":[{"type":"bold","attrs":{"future":7}}]}]},{"type":"paragraph","content":[{"type":"text","text":"Hello ","marks":[{"type":"bold"},{"type":"link","attrs":{"href":"https://example.invalid","future":"keep"}}]},{"type":"text","text":"world 👩🏽‍💻","marks":[{"type":"italic"},{"type":"underline"},{"type":"strike"},{"type":"code"}]},{"type":"inlineMath","attrs":{"latex":"x^2"}},{"type":"entryLink","attrs":{"entryId":"entry-target","label":"Related"}},{"type":"hardBreak"}]},{"type":"taskList","content":[{"type":"taskItem","attrs":{"checked":false,"future":{"keep":true}},"content":[{"type":"paragraph","content":[{"type":"text","text":"Task"}]}]}]},{"type":"table","attrs":{"future":1},"content":[{"type":"tableRow","content":[{"type":"tableHeader","attrs":{"colspan":1,"rowspan":1,"colwidth":[160]},"content":[{"type":"paragraph","content":[{"type":"text","text":"Header"}]}]},{"type":"tableCell","attrs":{"colspan":2,"rowspan":1,"colwidth":null},"content":[{"type":"paragraph","content":[{"type":"text","text":"Cell"}]}]}]}]},{"type":"mediaAttachment","attrs":{"id":"attachment","mime":"image/png","bytes":10,"name":"Public photo","kind":"image","transcript":"Public transcript"}},{"type":"mediaGallery","attrs":{"images":[{"id":"gallery","mime":"image/png","bytes":10,"name":"Public photo"}]}},{"type":"blockMath","attrs":{"latex":"\\frac{a}{b}"}},{"type":"blockquote","content":[{"type":"paragraph","content":[{"type":"text","text":"Quotation"}]}]},{"type":"codeBlock","attrs":{"language":"swift"},"content":[{"type":"text","text":"let answer = 42"}]},{"type":"bulletList","content":[{"type":"listItem","content":[{"type":"paragraph","content":[{"type":"text","text":"Bullet"}]}]}]},{"type":"orderedList","attrs":{"start":3},"content":[{"type":"listItem","content":[{"type":"paragraph","content":[{"type":"text","text":"Numbered"}]}]}]},{"type":"locationMap","attrs":{"from":{"label":"Home"},"to":{"label":"Park"},"map":{"id":"map","mime":"image/png","bytes":10,"name":"Public photo"},"photo":{"id":"photo","mime":"image/png","bytes":10,"name":"Public photo"},"future":[1,2]}},{"type":"videoInterview","attrs":{"typeName":"Public interview","cards":[{"q":"Question?","transcript":"Answer","clip":{"id":"clip","mime":"image/png","bytes":10,"name":"Public photo"}}],"film":{"id":"film","mime":"image/png","bytes":10,"name":"Public photo"}}},{"type":"futureNode","attrs":{"secretFormat":{"keep":[1,"two",false]}},"content":[{"type":"text","text":"Opaque future text","marks":[{"type":"futureMark","attrs":{"keep":true}}]}]}]}"# }
#endif
