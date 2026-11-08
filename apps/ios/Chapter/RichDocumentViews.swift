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
            var value = AttributedString(node.text), face = node.value["marks"].array.contains(where:{$0["type"].string == "code"}) ? chapterFont(.mono,skin:model.snapshot.appearance?.skin ?? "paper",size:16):font
            for mark in node.value["marks"].array {
                switch mark["type"].string {
                case "bold": face = face.bold()
                case "italic": face = face.italic()
                case "code": break // Spline Sans Mono selected before applying bold/italic.
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
            let font: Font = node.type == "heading"
                ? chapterFont(.heading,skin:model.snapshot.appearance?.skin ?? "paper",size:level == 1 ? 28:level == 2 ? 22:20,relativeTo:level == 1 ? .title:level == 2 ? .title2:.title3)
                : chapterFont(.prose,skin:model.snapshot.appearance?.skin ?? "paper",size:18)
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
                } label: { Image(systemName: checked ? "checkmark.square.fill" : "square").frame(minWidth: 44, minHeight: 44) }
                    .accessibilityLabel(checked ? "Mark task incomplete" : "Mark task complete")
                children(node)
            })
        case "blockquote": return AnyView(HStack(alignment: .top) { Rectangle().fill(Color.secondary).frame(width: 3); children(node) }.fixedSize(horizontal: false, vertical: true).padding(.leading, 6))
        case "codeBlock": return AnyView(ScrollView(.horizontal) { Text(node.children.map(\.text).joined()).font(chapterFont(.mono,skin:model.snapshot.appearance?.skin ?? "paper",size:16)).textSelection(.enabled) }.padding().background(chapterToken("surface",preference:model.snapshot.appearance ?? .standard), in: RoundedRectangle(cornerRadius: 8)))
        case "horizontalRule": return AnyView(Divider().accessibilityLabel("Separator"))
        case "table": return AnyView(ScrollView(.horizontal) { children(node) }.accessibilityLabel("Table; merged cell layout is simplified"))
        case "tableRow": return AnyView(HStack(alignment: .top, spacing: 0) { ForEach(node.children) { render($0).frame(minWidth: 140, alignment: .leading) } })
        case "tableCell", "tableHeader": return AnyView(children(node).padding(10).background(chapterToken("surface",preference:model.snapshot.appearance ?? .standard)).border(Color.secondary.opacity(0.4)))
        case "blockMath": return AnyView(Text(node.value["attrs"]["latex"].string ?? "").font(chapterFont(.mono,skin:model.snapshot.appearance?.skin ?? "paper",size:16)).textSelection(.enabled).accessibilityLabel("LaTeX formula: " + (node.value["attrs"]["latex"].string ?? "")))
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
    @Environment(\.dismiss) private var dismiss
    private var live: VaultRecord? { model.snapshot.records.first { $0.id == entry.id && !$0.deleted && $0.kind == "entry" } }
    var body: some View {
        NavigationStack {
            List {
                if let live, let raw = live.body["bodyJson"]?.string, let document = try? RichDocument(json: raw) {
                    Section {
                        Text("Changes preserve original custom nodes and formatting. Text and formatting drafts are saved encrypted; Apply updates the entry. New blocks support headings, lists, quotes and code. Selection-based editing and existing table restructuring are not yet complete.")
                        let pending = model.snapshot.richDrafts?.first { $0.entryID == live.id && $0.newBlockStyle != nil }
                        NavigationLink { RichDraftEditor(draft: pending ?? RichDraft.newBlock(entryID: live.id, expectedDocument: raw)) } label: { Label("Add block", systemImage: "plus") }.accessibilityIdentifier("rich.add-block")
                    }
                    Section {
                        NavigationLink { RichStructureEditor(entry: live) } label: { Label("Arrange blocks", systemImage: "arrow.up.arrow.down") }
                            .accessibilityIdentifier("rich.arrange-blocks")
                    }
                    Section("Text and empty blocks") {
                        ForEach(document.editableTextNodes) { leaf in
                            let draft = model.snapshot.richDrafts?.first { $0.entryID == live.id && $0.path == leaf.path && $0.newBlockStyle == nil }
                                ?? RichDraft(entryID: live.id, path: leaf.path, expectedDocument: raw, text: leaf.text)
                            NavigationLink { RichDraftEditor(draft: draft) } label: { Text(leaf.text.isEmpty ? "Empty " + leaf.type : leaf.text).lineLimit(3) }
                                .accessibilityIdentifier("rich.run." + leaf.id)
                        }
                    }
                } else { Text("This entry is no longer available for editing. Saved drafts remain in Settings.") }
            }.modifier(ChapterScreenSurface()).navigationTitle("Edit rich entry").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }
    }
}

struct RichStructureEditor: View {
    @EnvironmentObject private var model: VaultModel
    @State private var checkpoint: VaultRecord
    @State private var error: String?
    init(entry: VaultRecord) { _checkpoint = State(initialValue: entry) }
    private var blocks: [RichNode] { (try? RichDocument(json: checkpoint.body["bodyJson"]?.string ?? ""))?.node.children ?? [] }
    var body: some View {
        List {
            Section {
                Text("Drag whole blocks to rearrange your entry. Each move saves automatically. Text drafts are kept on their original version.").font(.footnote).foregroundStyle(.secondary)
            }
            Section("Document order") {
                ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title(block)).font(.headline)
                        if let text = preview(block), !text.isEmpty { Text(text).lineLimit(3).foregroundStyle(.secondary) }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("rich.block." + String(index))
                    .contextMenu {
                        if index > 0 { Button("Move up", systemImage: "arrow.up") { move(IndexSet(integer: index), to: index - 1) } }
                        if index + 1 < blocks.count { Button("Move down", systemImage: "arrow.down") { move(IndexSet(integer: index), to: index + 2) } }
                    }
                    .accessibilityAction(named: Text("Move up")) { if index > 0 { move(IndexSet(integer: index), to: index - 1) } }
                    .accessibilityAction(named: Text("Move down")) { if index + 1 < blocks.count { move(IndexSet(integer: index), to: index + 2) } }
                }.onMove { offsets, destination in move(offsets, to: destination) }
            }
        }.modifier(ChapterScreenSurface()).navigationTitle("Arrange blocks")
        .toolbar { EditButton() }
        .alert("Could not rearrange", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("Keep reviewing", role: .cancel) {}
            Button("Review latest saved entry") {
                if let latest = model.snapshot.records.first(where: { $0.id == checkpoint.id && !$0.deleted }) { checkpoint = latest }
            }
        } message: { Text((error ?? "") + " Your saved entry and text drafts were not overwritten.") }
    }
    private func move(_ offsets: IndexSet, to destination: Int) {
        do { checkpoint = try model.reorderRichBlocks(checkpoint, from: offsets, to: destination) }
        catch { self.error = error.localizedDescription }
    }
    private func title(_ node: RichNode) -> String {
        switch node.type {
        case "paragraph": return "Paragraph"
        case "heading": return "Heading"
        case "blockquote": return "Quote"
        case "codeBlock": return "Code"
        case "bulletList": return "Bulleted list"
        case "orderedList": return "Numbered list"
        case "taskList": return "Tasks"
        case "table": return "Table"
        case "mediaAttachment", "mediaGallery": return "Attachment"
        case "blockMath": return "Formula"
        case "locationMap": return "Location"
        case "videoInterview": return "Interview"
        case "horizontalRule": return "Separator"
        default: return node.type + " — preserved"
        }
    }
    private func preview(_ node: RichNode) -> String? {
        // Never interpret an unknown block's future payload as editable text.
        guard RichDocument.containers.contains(node.type) else { return node.value["attrs"]["name"].string }
        let wrapped: JSONValue = .object(["type": .string("doc"), "content": .array([node.value])])
        guard let data = try? JSONEncoder().encode(wrapped), let doc = try? RichDocument(json: String(decoding: data, as: UTF8.self)) else { return nil }
        return String(doc.plainText.prefix(240))
    }
}

struct RichDraftEditor: View {
    @EnvironmentObject private var model: VaultModel
    @Environment(\.dismiss) private var dismiss
    @State private var current: RichDraft
    @State private var error: String?
    @State private var savedDraft = false
    @State private var formattingExpanded = false
    private let formats = [("bold", "Bold"), ("italic", "Italic"), ("underline", "Underline"), ("strike", "Strikethrough"), ("code", "Inline code")]
    init(draft: RichDraft) { _current = State(initialValue: draft) }
    var body: some View {
        VStack(alignment: .leading) {
            if current.newBlockStyle != nil {
                Picker("Block style", selection: Binding(get: {current.newBlockStyle ?? .paragraph}, set: {current.newBlockStyle = $0})) {
                    ForEach(RichBlockStyle.allCases, id: \.self) { Text($0.title).tag($0) }
                }.pickerStyle(.menu).padding().accessibilityIdentifier("rich.block-style")
            }
            if current.supportsFormatting {
                Button("Formatting") { formattingExpanded.toggle() }.accessibilityValue(formattingExpanded ? "Expanded":"Collapsed")
                    .frame(minWidth:44,minHeight:44).padding(.horizontal).accessibilityIdentifier("rich.formatting")
                if formattingExpanded {
                    VStack(alignment:.leading) {
                        ForEach(formats,id:\.0) { type,title in
                            Button {
                                do { current = try current.togglingMark(type); formattingExpanded = false }
                                catch { self.error = error.localizedDescription }
                            } label: { Label(title,systemImage:current.hasMark(type) ? "checkmark":"circle").frame(maxWidth:.infinity,minHeight:44,alignment:.leading) }
                                .buttonStyle(.bordered).accessibilityIdentifier("rich.format." + type)
                        }
                    }.padding(.horizontal)
                }
            }
            TextEditor(text: $current.text).font(chapterFont(.prose,skin:model.snapshot.appearance?.skin ?? "paper",size:18)).scrollContentBackground(.hidden).background(chapterToken("paper",preference:model.snapshot.appearance ?? .standard)).accessibilityLabel(current.newBlockStyle == nil ? "Formatted text run" : "New block text").autocorrectionDisabled().padding()
            if current.supportsFormatting {
                Text("Formatting: " + (formats.contains(where: { current.hasMark($0.0) }) ? formats.filter { current.hasMark($0.0) }.map { $0.1 }.joined(separator: ", ") : "Plain text")).font(.footnote).padding(.horizontal).accessibilityIdentifier("rich.format-summary")
            }
            Text(error ?? (savedDraft ? "Draft saved encrypted on this device. Tap Save to update the entry." : "Edits stay in an encrypted draft until Save. Other formatting and unknown content remain intact.")).font(.footnote).padding()
        }.modifier(ChapterScreenSurface()).navigationTitle(current.newBlockStyle == nil ? "Edit text" : "Add block")
        .toolbar {
            Button("Save") {
                do { try model.applyRichDraft(current); dismiss() } catch { self.error = error.localizedDescription }
            }.disabled(current.newBlockStyle != nil && current.text.isEmpty)
        }
        .onChange(of: current) { _, _ in
            savedDraft = false
            do { try model.saveRichDraft(current); savedDraft = true; error = nil } catch { self.error = error.localizedDescription }
        }
        .interactiveDismissDisabled(error != nil)
    }
}

#if DEBUG
// Public fixture only; never a way to unlock a real vault or bypass Keychain.
enum PublicRichFixture { static let json = #"{"type":"doc","futureRoot":{"keep":["all",1,true]},"content":[{"type":"heading","attrs":{"level":2,"future":"keep"},"content":[{"type":"text","text":"Public heading","marks":[{"type":"bold","attrs":{"future":7}}]}]},{"type":"paragraph","content":[{"type":"text","text":"Hello ","marks":[{"type":"bold"},{"type":"link","attrs":{"href":"https://example.invalid","future":"keep"}}]},{"type":"text","text":"world 👩🏽‍💻","marks":[{"type":"italic"},{"type":"underline"},{"type":"strike"},{"type":"code"}]},{"type":"inlineMath","attrs":{"latex":"x^2"}},{"type":"entryLink","attrs":{"entryId":"entry-target","label":"Related"}},{"type":"hardBreak"}]},{"type":"taskList","content":[{"type":"taskItem","attrs":{"checked":false,"future":{"keep":true}},"content":[{"type":"paragraph","content":[{"type":"text","text":"Task"}]}]}]},{"type":"table","attrs":{"future":1},"content":[{"type":"tableRow","content":[{"type":"tableHeader","attrs":{"colspan":1,"rowspan":1,"colwidth":[160]},"content":[{"type":"paragraph","content":[{"type":"text","text":"Header"}]}]},{"type":"tableCell","attrs":{"colspan":2,"rowspan":1,"colwidth":null},"content":[{"type":"paragraph","content":[{"type":"text","text":"Cell"}]}]}]}]},{"type":"mediaAttachment","attrs":{"id":"attachment","mime":"image/png","bytes":10,"name":"Public photo","kind":"image","transcript":"Public transcript"}},{"type":"mediaGallery","attrs":{"images":[{"id":"gallery","mime":"image/png","bytes":10,"name":"Public photo"}]}},{"type":"blockMath","attrs":{"latex":"\\frac{a}{b}"}},{"type":"blockquote","content":[{"type":"paragraph","content":[{"type":"text","text":"Quotation"}]}]},{"type":"codeBlock","attrs":{"language":"swift"},"content":[{"type":"text","text":"let answer = 42"}]},{"type":"bulletList","content":[{"type":"listItem","content":[{"type":"paragraph","content":[{"type":"text","text":"Bullet"}]}]}]},{"type":"orderedList","attrs":{"start":3},"content":[{"type":"listItem","content":[{"type":"paragraph","content":[{"type":"text","text":"Numbered"}]}]}]},{"type":"locationMap","attrs":{"from":{"label":"Home"},"to":{"label":"Park"},"map":{"id":"map","mime":"image/png","bytes":10,"name":"Public photo"},"photo":{"id":"photo","mime":"image/png","bytes":10,"name":"Public photo"},"future":[1,2]}},{"type":"videoInterview","attrs":{"typeName":"Public interview","cards":[{"q":"Question?","transcript":"Answer","clip":{"id":"clip","mime":"image/png","bytes":10,"name":"Public photo"}}],"film":{"id":"film","mime":"image/png","bytes":10,"name":"Public photo"}}},{"type":"futureNode","attrs":{"secretFormat":{"keep":[1,"two",false]}},"content":[{"type":"text","text":"Opaque future text","marks":[{"type":"futureMark","attrs":{"keep":true}}]}]}]}"# }
#endif
