// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI
import ChapterCore

struct RichDocumentView: View {
    @EnvironmentObject private var model: VaultModel
    let entry: VaultRecord
    let document: RichDocument
    @State private var error: String?
    @State private var externalURL: URL?
    @State private var linkedEntry: LocalEntryDestination?
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            render(document.node)
            Text("Native rich preview: math is shown as LaTeX; merged-table layout and custom media/interview cards are simplified. Unknown nodes and formatting remain intact.").font(.footnote).foregroundStyle(.secondary)
        }
        .navigationDestination(item:$linkedEntry) { destination in LinkedEntryDestination(entryID:destination.id) }
        .environment(\.openURL, OpenURLAction { url in
            if let id=EntryLinkRoute.entryID(from:url) {linkedEntry=LocalEntryDestination(id:id);return .handled}
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
        if node.type == "entryLink" {
            let id=node.value["attrs"]["entryId"].string ?? ""
            let current=model.entries.first(where:{$0.id.utf8.elementsEqual(id.utf8)})
            var value=AttributedString(current?.title ?? node.value["attrs"]["label"].string ?? "Related entry")
            value.link=EntryLinkRoute.url(for:id);value.underlineStyle = .single;value.font=font;return value
        }
        if !["paragraph", "heading"].contains(node.type) { return AttributedString("[\(node.type) — preserved]") }
        return node.children.reduce(into: AttributedString()) { $0 += inline($1, font: font) }
    }
    /// Original DocPreview marker: UI face at 0.82em, ink-3, 1px dashed line, radius 9.
    private func customChip(_ text: String) -> some View {
        let preference = model.snapshot.appearance ?? .standard
        return Text(text).font(chapterFont(.ui, skin: preference.skin, size: 15, relativeTo: .subheadline))
            .foregroundStyle(chapterToken("ink-3", preference: preference))
            .padding(.vertical, 4).padding(.horizontal, 10)
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(chapterToken("line", preference: preference), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
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
        case "table":
            guard let grid = RichTableLayout(table: node) else { return AnyView(ScrollView(.horizontal) { children(node) }.accessibilityLabel("Table; this layout could not be read exactly and is simplified")) }
            let preference = model.snapshot.appearance ?? .standard
            return AnyView(ScrollView(.horizontal) {
                RichTableGrid(layout: grid) {
                    ForEach(Array(grid.cells.enumerated()), id: \.offset) { _, cell in
                        let value = node.childAt(cell.path).map { RichNode(value: $0, path: cell.path) }
                        VStack(alignment: .leading, spacing: 4) { if let value { ForEach(value.children) { render($0) } } }
                            .font(chapterFont(.ui, skin: preference.skin, size: 15, relativeTo: .subheadline).weight(cell.header ? .semibold : .regular))
                            .padding(.vertical, 7).padding(.horizontal, 10)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .background(cell.header ? chapterToken("surface-2", preference: preference) : Color.clear)
                            .overlay(Rectangle().stroke(chapterToken("line", preference: preference), lineWidth: 1))
                            .accessibilityElement(children: .contain)
                            .accessibilityLabel((cell.header ? "Header, " : "") + "row \(cell.row + 1), column \(cell.column + 1)" + (cell.rowSpan > 1 || cell.columnSpan > 1 ? ", spans \(cell.rowSpan) rows and \(cell.columnSpan) columns" : ""))
                            .accessibilityIdentifier("table.cell.\(cell.row).\(cell.column)")
                    }
                }
            }.accessibilityElement(children: .contain).accessibilityLabel("Table, \(grid.height) rows, \(grid.width) columns"))
        case "tableRow": return AnyView(HStack(alignment: .top, spacing: 0) { ForEach(node.children) { render($0).frame(minWidth: 140, alignment: .leading) } })
        case "tableCell", "tableHeader": return AnyView(children(node).padding(10).background(chapterToken("surface",preference:model.snapshot.appearance ?? .standard)).border(Color.secondary.opacity(0.4)))
        case "blockMath": return AnyView(Text(node.value["attrs"]["latex"].string ?? "").font(chapterFont(.mono,skin:model.snapshot.appearance?.skin ?? "paper",size:16)).textSelection(.enabled).accessibilityLabel("LaTeX formula: " + (node.value["attrs"]["latex"].string ?? "")))
        case "mediaAttachment", "mediaGallery": return AnyView(Label(node.value["attrs"]["name"].string ?? "Encrypted media — use attachment preview below", systemImage: "paperclip").foregroundStyle(.secondary))
        case "locationMap": return AnyView(customChip(RichCustomBlockLabel.location(node.value["attrs"])).textSelection(.enabled).accessibilityIdentifier("custom.location"))
        case "videoInterview": return AnyView(VStack(alignment: .leading, spacing: 8) {
            customChip(RichCustomBlockLabel.videoInterview(node.value["attrs"])).accessibilityIdentifier("custom.videoInterview")
            ForEach(Array(node.value["attrs"]["cards"].array.enumerated()), id: \.offset) { _, card in
                Text(card["q"].string ?? "").font(.headline); Text(card["transcript"].string ?? "")
            }
        })
        default: return AnyView(Text("Unsupported \(node.type) node — preserved unchanged").font(.footnote).foregroundStyle(.secondary))
        }
    }
}

/// The original table toolbar: choose the cell the cursor would be in, then run
/// the same prosemirror-tables command. Merged-cell tables are left read-only.
struct RichTableEditor: View {
    @EnvironmentObject private var model: VaultModel
    @Environment(\.dismiss) private var dismiss
    let entryID: String
    let path: [Int]
    @State private var row = 0
    @State private var column = 0
    @State private var error: String?
    @State private var confirmDelete = false
    private var live: VaultRecord? { model.snapshot.records.first { $0.id == entryID && !$0.deleted && $0.kind == "entry" } }
    private var rows: [[JSONValue]]? { live?.body["bodyJson"]?.string.flatMap { try? RichDocument(json: $0) }?.editableTableRows(at: path) }
    var body: some View {
        Form {
            if let rows {
                Section {
                    ForEach(rows.indices, id: \.self) { r in
                        ScrollView(.horizontal) {
                            HStack {
                                ForEach(rows[r].indices, id: \.self) { c in
                                    let text = RichDocument.cellText(rows[r][c])
                                    let header = rows[r][c]["type"].string == "tableHeader"
                                    Button { row = r; column = c } label: {
                                        Text(text.isEmpty ? "Empty" : text).font(header ? .headline : .body).frame(minWidth: 88, minHeight: 44)
                                    }.buttonStyle(.bordered).tint(r == row && c == column ? .accentColor : .gray)
                                        .accessibilityLabel("Row \(r + 1), column \(c + 1)\(header ? ", header" : ""): \(text.isEmpty ? "empty" : text)")
                                        .accessibilityAddTraits(r == row && c == column ? .isSelected : [])
                                        .accessibilityIdentifier("table.cell.\(r).\(c)")
                                }
                            }
                        }
                    }
                } header: { Text("Choose a cell") } footer: { Text("Selected: row \(row + 1), column \(column + 1). Commands act like the original toolbar with the cursor in this cell.") }
                Section("Table") {
                    ForEach(RichTableCommand.allCases, id: \.self) { command in
                        Button(command.title, role: [.deleteRow, .deleteColumn, .deleteTable].contains(command) ? .destructive : nil) {
                            if command == .deleteTable { confirmDelete = true } else { run(command, rows: rows) }
                        }.disabled((command == .deleteRow && rows.count < 2) || (command == .deleteColumn && rows[0].count < 2))
                            .accessibilityIdentifier("table.command." + command.rawValue)
                    }
                }
                if let error { Text(error).accessibilityIdentifier("table.error") }
            } else {
                Text("This table has merged cells or is no longer available. It is preserved exactly; edit its structure in the web app.").accessibilityIdentifier("table.unsupported")
            }
        }.modifier(ChapterScreenSurface()).navigationTitle("Edit table")
        .confirmationDialog("Delete this table?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete table", role: .destructive) { if let rows { run(.deleteTable, rows: rows) } }.accessibilityIdentifier("table.confirmDelete")
        } message: { Text("The table and its contents are removed from this entry.") }
    }
    private func run(_ command: RichTableCommand, rows: [[JSONValue]]) {
        do {
            guard let live else { throw ChapterError.conflict }
            try model.applyTableCommand(live, command: command, table: path, row: row, column: column)
            error = nil
            if command == .deleteTable { dismiss(); return }
            if let next = self.rows { row = min(row, next.count - 1); column = min(column, next[0].count - 1) }
        } catch { self.error = "The table changed or can’t take this command. Nothing was lost. " + error.localizedDescription }
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
                        Text("Changes preserve original custom nodes and formatting. Text and formatting drafts are saved encrypted; Apply updates the entry. New blocks support headings, lists, quotes and code. In a text run, place the cursor to insert an entry link or template there, or select text to format just that part (iOS 18). Tables without merged cells can gain or lose rows and columns.")
                        let pending = model.snapshot.richDrafts?.first { $0.entryID == live.id && $0.newBlockStyle != nil }
                        NavigationLink { RichDraftEditor(draft: pending ?? RichDraft.newBlock(entryID: live.id, expectedDocument: raw)) } label: { Label("Add block", systemImage: "plus") }.accessibilityIdentifier("rich.add-block")
                    }
                    Section {
                        NavigationLink { RichStructureEditor(entry: live) } label: { Label("Arrange blocks", systemImage: "arrow.up.arrow.down") }
                            .accessibilityIdentifier("rich.arrange-blocks")
                    }
                    let tables = document.tablePaths
                    if !tables.isEmpty {
                        Section("Tables") {
                            ForEach(Array(tables.enumerated()), id: \.offset) { number, path in
                                NavigationLink { RichTableEditor(entryID: live.id, path: path) } label: { Label("Table \(number + 1)", systemImage: "tablecells") }
                                    .accessibilityIdentifier("rich.table." + path.map(String.init).joined(separator: "/"))
                            }
                        }
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
    @State private var caret: Int?
    @State private var selected: Range<Int>?
    @State private var insertion: CaretInsertion?
    private static var caretSupported: Bool { if #available(iOS 18.0, *) { return true } else { return false } }
    private let formats = [("bold", "Bold"), ("italic", "Italic"), ("underline", "Underline"), ("strike", "Strikethrough"), ("code", "Inline code")]
    init(draft: RichDraft) { _current = State(initialValue: draft) }
    var body: some View {
        VStack(alignment: .leading) {
            if current.newBlockStyle != nil {
                Picker("Block style", selection: Binding(get: {current.newBlockStyle ?? .paragraph}, set: {current.newBlockStyle = $0})) {
                    ForEach(RichBlockStyle.allCases, id: \.self) { Text($0.title).tag($0) }
                }.pickerStyle(.menu).padding().accessibilityIdentifier("rich.block-style")
            }
            Group {
                if #available(iOS 18.0, *) {
                    if current.newBlockStyle == nil { CaretTrackingEditor(text: $current.text, caret: $caret, selected: $selected) } else { TextEditor(text: $current.text) }
                } else {
                    TextEditor(text: $current.text)
                }
            }.font(chapterFont(.prose,skin:model.snapshot.appearance?.skin ?? "paper",size:18)).scrollContentBackground(.hidden).background(chapterToken("paper",preference:model.snapshot.appearance ?? .standard)).accessibilityLabel(current.newBlockStyle == nil ? "Formatted text run" : "New block text").autocorrectionDisabled().padding()
            if current.supportsFormatting {
                Button("Formatting") { formattingExpanded.toggle() }.accessibilityValue(formattingExpanded ? "Expanded":"Collapsed")
                    .frame(minWidth:44,minHeight:44).padding(.horizontal).accessibilityIdentifier("rich.formatting")
                if formattingExpanded {
                    VStack(alignment:.leading) {
                        ForEach(formats,id:\.0) { type,title in
                            Button {
                                if let selected, current.newBlockStyle == nil { format(type, selection: selected) }
                                else {
                                    do { current = try current.togglingMark(type); formattingExpanded = false }
                                    catch { self.error = error.localizedDescription }
                                }
                            } label: { Label(title,systemImage:current.hasMark(type) ? "checkmark":"circle").frame(maxWidth:.infinity,minHeight:44,alignment:.leading) }
                                .buttonStyle(.bordered).accessibilityIdentifier("rich.format." + type)
                        }
                        if selected != nil { Text("With text selected, formatting applies to the selection and saves the entry, like the original toolbar.").font(.footnote).accessibilityIdentifier("rich.selection-hint") }
                    }.padding(.horizontal)
                }
            }
            if current.newBlockStyle == nil && Self.caretSupported {
                HStack {
                    Button { prepare(link: true) } label: { Label("Insert link here", systemImage: "link").frame(minHeight: 44) }.accessibilityIdentifier("rich.insert-link")
                    Button { prepare(link: false) } label: { Label("Insert template here", systemImage: "doc.on.doc").frame(minHeight: 44) }.accessibilityIdentifier("rich.insert-template")
                }.buttonStyle(.bordered).disabled(caret == nil).padding(.horizontal)
                if caret == nil { Text("Tap in the text to place the cursor (without selecting text) to insert a link or template there.").font(.footnote).padding(.horizontal).accessibilityIdentifier("rich.caret-hint") }
            }
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
        .sheet(item: $insertion) { item in
            if item.link { EntryLinkPicker(entry: item.entry, caret: item.caret) { dismiss() } }
            else { TemplateInsertPicker(entry: item.entry, caret: item.caret) { dismiss() } }
        }
    }
    /// Saves pending text first (so the cursor refers to what you see), then
    /// maps the editor cursor onto the original document for the picker.
    private func prepare(link: Bool) {
        do {
            guard let caret else { throw ChapterError.unsupported }
            let (record, raw) = try committed()
            let point = try RichDocument(json: raw).caret(leaf: current.path, utf16Offset: caret)
            insertion = CaretInsertion(link: link, entry: record, caret: point)
            error = nil
        } catch { self.error = "Place the cursor in text that still exists, then try again. Your writing was kept. " + error.localizedDescription }
    }
    /// Saves pending text first, so positions refer to exactly what you see.
    private func committed() throws -> (VaultRecord, String) {
        func live() -> VaultRecord? { model.snapshot.records.first { $0.id == current.entryID && !$0.deleted && $0.kind == "entry" } }
        guard let record = live(), let raw = record.body["bodyJson"]?.string else { throw ChapterError.conflict }
        let leaf = try RichDocument(json: raw).editableTextNodes.first { $0.path == current.path }
        let leafText = leaf?.type == "text" ? leaf?.text : ""
        guard leafText.map({ Data($0.utf8) != Data(current.text.utf8) }) ?? true || current.marks != nil else { return (record, raw) }
        try model.applyRichDraft(current)
        guard let saved = live(), let savedRaw = saved.body["bodyJson"]?.string else { throw ChapterError.conflict }
        return (saved, savedRaw)
    }
    /// Original toolbar toggleMark over the selected part of this run.
    private func format(_ type: String, selection: Range<Int>) {
        do {
            let (record, raw) = try committed()
            // A run typed into an empty block becomes that block's first text node.
            let nodes = try RichDocument(json: raw).editableTextNodes
            guard let leaf = nodes.first(where: { $0.path == current.path && $0.type == "text" }) ?? nodes.first(where: { $0.path == current.path + [0] && $0.type == "text" }) else { throw ChapterError.unsupported }
            try model.toggleSelectionMark(record, type: type, leaf: leaf.path, range: selection)
            dismiss()
        } catch { self.error = "That selection can’t take this formatting (for example inside inline code or a link). Your writing was kept. " + error.localizedDescription }
    }
}
private struct CaretInsertion: Identifiable { let link: Bool; let entry: VaultRecord; let caret: RichCaret; var id: String { (link ? "link:" : "template:") + caret.block.map(String.init).joined(separator: "/") + ":" + String(caret.offset) } }
/// iOS 18 TextEditor selection, reported as a collapsed UTF-16 cursor offset or a selected range.
@available(iOS 18.0, *)
struct CaretTrackingEditor: View {
    @Binding var text: String
    @Binding var caret: Int?
    @Binding var selected: Range<Int>?
    @State private var selection: TextSelection?
    var body: some View {
        TextEditor(text: $text, selection: Binding(get: { selection }, set: { value in
            selection = value
            caret = Self.offset(value, in: text); selected = Self.range(value, in: text)
        }))
        .onChange(of: text) { _, newText in caret = Self.offset(selection, in: newText); selected = Self.range(selection, in: newText) }
    }
    /// A non-empty selection as a UTF-16 range of this run's text.
    static func range(_ selection: TextSelection?, in text: String) -> Range<Int>? {
        guard let selection, case .selection(let range) = selection.indices, !range.isEmpty, range.upperBound <= text.endIndex,
              let start = range.lowerBound.samePosition(in: text.utf16), let end = range.upperBound.samePosition(in: text.utf16) else { return nil }
        let utf16 = text.utf16
        return utf16.distance(from: utf16.startIndex, to: start)..<utf16.distance(from: utf16.startIndex, to: end)
    }
    static func offset(_ selection: TextSelection?, in text: String) -> Int? {
        guard let selection, case .selection(let range) = selection.indices, range.isEmpty,
              range.lowerBound <= text.endIndex, let point = range.lowerBound.samePosition(in: text.utf16) else { return nil }
        return text.utf16.distance(from: text.utf16.startIndex, to: point)
    }
}

#if DEBUG
// Public fixture only; never a way to unlock a real vault or bypass Keychain.
enum PublicRichFixture { static let json = #"{"type":"doc","futureRoot":{"keep":["all",1,true]},"content":[{"type":"heading","attrs":{"level":2,"future":"keep"},"content":[{"type":"text","text":"Public heading","marks":[{"type":"bold","attrs":{"future":7}}]}]},{"type":"paragraph","content":[{"type":"text","text":"Hello ","marks":[{"type":"bold"},{"type":"link","attrs":{"href":"https://example.invalid","future":"keep"}}]},{"type":"text","text":"world 👩🏽‍💻","marks":[{"type":"italic"},{"type":"underline"},{"type":"strike"},{"type":"code"}]},{"type":"inlineMath","attrs":{"latex":"x^2"}},{"type":"entryLink","attrs":{"entryId":"entry-target","label":"Related"}},{"type":"hardBreak"}]},{"type":"taskList","content":[{"type":"taskItem","attrs":{"checked":false,"future":{"keep":true}},"content":[{"type":"paragraph","content":[{"type":"text","text":"Task"}]}]}]},{"type":"table","attrs":{"future":1},"content":[{"type":"tableRow","content":[{"type":"tableHeader","attrs":{"colspan":1,"rowspan":1,"colwidth":[160]},"content":[{"type":"paragraph","content":[{"type":"text","text":"Header"}]}]},{"type":"tableCell","attrs":{"colspan":2,"rowspan":1,"colwidth":null},"content":[{"type":"paragraph","content":[{"type":"text","text":"Cell"}]}]}]}]},{"type":"mediaAttachment","attrs":{"id":"attachment","mime":"image/png","bytes":10,"name":"Public photo","kind":"image","transcript":"Public transcript"}},{"type":"mediaGallery","attrs":{"images":[{"id":"gallery","mime":"image/png","bytes":10,"name":"Public photo"}]}},{"type":"blockMath","attrs":{"latex":"\\frac{a}{b}"}},{"type":"blockquote","content":[{"type":"paragraph","content":[{"type":"text","text":"Quotation"}]}]},{"type":"codeBlock","attrs":{"language":"swift"},"content":[{"type":"text","text":"let answer = 42"}]},{"type":"bulletList","content":[{"type":"listItem","content":[{"type":"paragraph","content":[{"type":"text","text":"Bullet"}]}]}]},{"type":"orderedList","attrs":{"start":3},"content":[{"type":"listItem","content":[{"type":"paragraph","content":[{"type":"text","text":"Numbered"}]}]}]},{"type":"locationMap","attrs":{"from":{"label":"Home"},"to":{"label":"Park"},"map":{"id":"map","mime":"image/png","bytes":10,"name":"Public photo"},"photo":{"id":"photo","mime":"image/png","bytes":10,"name":"Public photo"},"future":[1,2]}},{"type":"videoInterview","attrs":{"typeName":"Public interview","cards":[{"q":"Question?","transcript":"Answer","clip":{"id":"clip","mime":"image/png","bytes":10,"name":"Public photo"}}],"film":{"id":"film","mime":"image/png","bytes":10,"name":"Public photo"}}},{"type":"futureNode","attrs":{"secretFormat":{"keep":[1,"two",false]}},"content":[{"type":"text","text":"Opaque future text","marks":[{"type":"futureMark","attrs":{"keep":true}}]}]}]}"# }
#endif

private struct LocalEntryDestination:Hashable {let id:String}
struct LinkedEntryDestination:View {
    @EnvironmentObject private var model:VaultModel
    let entryID:String
    private var downloaded:VaultRecord? {model.snapshot.records.first{$0.id.utf8.elementsEqual(entryID.utf8) && $0.kind=="entry"}}
    var body:some View {
        if let downloaded,!downloaded.deleted {EntryDetail(entryID:entryID)}
        else {
            VStack(alignment:.leading,spacing:16) {
                Label(downloaded?.deleted == true ? "Linked entry is deleted":"Linked entry is not downloaded",systemImage:"link").font(.title2).accessibilityAddTraits(.isHeader)
                Text(downloaded?.deleted == true ? "Look in Settings for a retained recovery copy. Opening a link never silently restores or overwrites writing.":"The original link is preserved. Sync your own server to download available entries; offline links only open entries already on this device.")
                if model.canSync {Button {Task{await model.sync()}} label:{if model.syncing {ProgressView("Syncing your server")} else {Text("Sync your server")}}.disabled(model.syncing)}
            }.padding().frame(maxWidth:.infinity,alignment:.leading).modifier(ChapterScreenSurface()).navigationTitle("Linked entry").accessibilityIdentifier("entry.link-unavailable")
        }
    }
}

/// Places each original table cell over its exact prosemirror-tables rectangle.
/// Column widths: agreed TipTap colwidth, else natural width within 96–280 pt.
struct RichTableGrid: Layout {
        let layout: RichTableLayout
        func tracks(_ subviews: Subviews) -> (columns: [CGFloat], rows: [CGFloat]) {
            var columns = layout.columnWidths.map { $0.map { CGFloat($0) } ?? 96 }
            let fixed = layout.columnWidths.map { $0 != nil }
            for (cell, view) in zip(layout.cells, subviews) where cell.columnSpan == 1 && cell.column < columns.count && !fixed[cell.column] {
                columns[cell.column] = max(columns[cell.column], min(280, view.sizeThatFits(.unspecified).width))
            }
            for (cell, view) in zip(layout.cells, subviews) where cell.columnSpan > 1 {
                let range = cell.column..<min(cell.column + cell.columnSpan, columns.count)
                let have = range.reduce(0) { $0 + columns[$1] }, want = min(280 * CGFloat(range.count), view.sizeThatFits(.unspecified).width)
                let free = range.filter { !fixed[$0] }
                if want > have, !free.isEmpty { for c in free { columns[c] += (want - have) / CGFloat(free.count) } }
            }
            var rows = [CGFloat](repeating: 44, count: layout.height)
            func width(_ cell: RichTableLayout.Cell) -> CGFloat { (cell.column..<min(cell.column + cell.columnSpan, columns.count)).reduce(0) { $0 + columns[$1] } }
            for (cell, view) in zip(layout.cells, subviews) where cell.rowSpan == 1 && cell.row < rows.count {
                rows[cell.row] = max(rows[cell.row], view.sizeThatFits(ProposedViewSize(width: width(cell), height: nil)).height)
            }
            for (cell, view) in zip(layout.cells, subviews) where cell.rowSpan > 1 {
                let range = cell.row..<min(cell.row + cell.rowSpan, rows.count)
                let have = range.reduce(0) { $0 + rows[$1] }, want = view.sizeThatFits(ProposedViewSize(width: width(cell), height: nil)).height
                if want > have, let last = range.last { rows[last] += want - have }
            }
            return (columns, rows)
        }
        func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
            let t = tracks(subviews); return CGSize(width: t.columns.reduce(0, +), height: t.rows.reduce(0, +))
        }
        func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
            let t = tracks(subviews)
            for (cell, view) in zip(layout.cells, subviews) {
                let x = t.columns.prefix(cell.column).reduce(0, +), y = t.rows.prefix(cell.row).reduce(0, +)
                let w = t.columns.dropFirst(cell.column).prefix(cell.columnSpan).reduce(0, +), h = t.rows.dropFirst(cell.row).prefix(cell.rowSpan).reduce(0, +)
                view.place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + y), anchor: .topLeading, proposal: ProposedViewSize(width: w, height: h))
            }
        }
    }
