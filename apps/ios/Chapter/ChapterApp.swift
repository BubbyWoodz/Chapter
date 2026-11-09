// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import CoreTransferable
import ChapterCore
import QuickLook

@main struct ChapterApp: App {
    init() {
        #if DEBUG
        UIView.setAnimationsEnabled(!ProcessInfo.processInfo.arguments.contains("--chapter-still-captures"))
        #endif
    }

    @StateObject private var model = VaultModel()
    @Environment(\.scenePhase) private var phase
    @ViewBuilder private var normalContent: some View {
        if model.unlocked { ChapterTabs().task { await model.runForegroundSync() } } else { ConnectView() }
    }
    @ViewBuilder private var rootContent: some View {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--chapter-native-form-audit-repro") {
            NativeFormAuditReproduction()
        } else if ProcessInfo.processInfo.arguments.contains("--chapter-full-width-action-audit-repro") {
            NativeFullWidthActionAuditReproduction()
        } else if ProcessInfo.processInfo.arguments.contains("--chapter-font-diagnostic") {
            ChapterFontDiagnostic()
        } else if ProcessInfo.processInfo.arguments.contains("--chapter-native-secure-field-audit-repro") {
            NativeSecureFieldAuditReproduction()
        } else { normalContent }
        #else
        normalContent
        #endif
    }
    var body: some Scene {
        WindowGroup {
            ZStack {
                rootContent
                if phase != .active { Color(uiColor: .systemBackground).ignoresSafeArea().overlay(Text("Chapter").font(.title)) }
            }
            .modifier(ChapterAppearanceStyle(preference: model.snapshot.appearance ?? .standard))
            .modifier(ChapterLanguageStyle(language: model.language))
            .environmentObject(model)
            .onAppear {
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--chapter-rich-fixture") { do { try model.loadPublicRichFixture() } catch { model.message = error.localizedDescription } }
                #endif
            }
            .onChange(of: phase) { _, value in if value == .background { model.lock() } }
            .privacySensitive()
        }
    }
}

/// Public minimal diagnostic, not an alternate production onboarding/audit path.
private struct NativeFormAuditReproduction: View {
    @State private var text = ""
    var body: some View {
        NavigationStack {
            Form {
                Text("Native Form reproduction").font(.headline)
                TextField("Public text", text: $text)
                Button("Public native action") { text = "Tapped" }
                    .accessibilityIdentifier("repro.native-button")
            }.navigationTitle("Audit reproduction")
        }
    }
}
struct ConnectView: View {
    @EnvironmentObject private var model: VaultModel
    @State private var server = UserDefaults.standard.string(forKey: "chapter.server") ?? ""
    @State private var phrase = ""
    private enum Field:Hashable {case server,phrase}
    @FocusState private var focusedField:Field?
    var body: some View {
        NavigationStack {
            // Footnotes use the full ink colour: secondary grey failed the strict
            // contrast audit ("Contrast nearly passed") on Apple CI (3bcde6e).
            // Every text uses a scaling text style. Apple CI
            // (cd787e8) showed system Section header/footer text only partially
            // scales ("Dynamic Type font sizes are partially unsupported" on the
            // UNLOCK VAULT header at XXXL and the phrase footer), and the earlier
            // fixedSize rows with overriding field labels failed outright.
            // A Debug bisection on Apple CI (0ca803f, run 42607615562) isolated the
            // remaining finding to long wrapping Text rows in a Form, and growing those
            // rows did not help (run 42614136563, "element: unknown"). A Form is a lazy
            // list: once the rows outgrow the screen, cells leave the hierarchy while the
            // audit resizes text. This screen is therefore a non-lazy ScrollView/VStack
            // of grouped cards, so every element exists at every text size.
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ConnectCard {
                        Text("Your journal. Your server.").font(.title2).accessibilityAddTraits(.isHeader).accessibilityIdentifier("connection.heading")
                        Text("Connect directly over your local network or Tailscale. No Chapter account is required.")
                        Text("Native preview: feature coverage is incomplete. Use the web app for advanced features and recovery-phrase creation/rotation.").font(.footnote)
                    }
                    ConnectCard {
                        Text("Server").font(.headline).accessibilityAddTraits(.isHeader)
                        TextField("Server URL", text: $server).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled().frame(minHeight: 44).accessibilityIdentifier("connection.server").focused($focusedField,equals:.server).submitLabel(.next).onSubmit {focusedField = .phrase}
                        Text("HTTPS with a trusted certificate is required, including on Tailscale. Include your server’s path prefix.").font(.footnote)
                    }
                    ConnectCard {
                        Text("Unlock vault").font(.headline).accessibilityAddTraits(.isHeader)
                        SecureField("12-word recovery phrase", text: $phrase).frame(minHeight: 44).accessibilityIdentifier("connection.phrase").focused($focusedField,equals:.phrase).submitLabel(.done).onSubmit {focusedField=nil}.textInputAutocapitalization(.never).autocorrectionDisabled().privacySensitive()
                        Text("The phrase stays on this device and is not saved. A device passcode is required to protect offline journals. Face ID or device authentication protects the local storage key.").font(.footnote)
                    }
                    if let message = model.message { ConnectCard { Text(message).accessibilityLabel("Connection status: \(message)").accessibilityIdentifier("connection.status") } }
                }.padding()
            }.modifier(ChapterScreenSurface()).navigationTitle("Chapter").scrollDismissesKeyboard(.interactively)
                .safeAreaInset(edge:.bottom) {
                    Button {
                        guard !model.connecting else { return }
                        guard !server.isEmpty, !phrase.isEmpty else {
                            model.message="Enter your server URL and recovery phrase.";return
                        }
                        focusedField=nil
                        let input=phrase;phrase=""
                        Task { await model.unlock(server:server,phrase:input) }
                    } label: {
                        Text(model.connecting ? "Connecting…":"Unlock and connect")
                            .font(.body).multilineTextAlignment(.center).fixedSize(horizontal:false,vertical:true)
                            .foregroundStyle(chapterToken("paper",preference:model.snapshot.appearance ?? .standard))
                            .frame(maxWidth:.infinity,minHeight:44)
                    }.buttonStyle(.borderedProminent).tint(chapterToken("ink",preference:model.snapshot.appearance ?? .standard)).disabled(model.connecting)
                        .accessibilityIdentifier("connection.unlock").padding().background(.regularMaterial)
                }
        }
    }
}

/// The entry's text as one large selectable block, with Copy (web common.copy).
struct SelectableEntryText: View {
    @EnvironmentObject private var model: VaultModel
    @Environment(\.dismiss) private var dismiss
    let title: String, text: String
    @State private var copied = false
    var body: some View {
        NavigationStack {
            ScrollView {
                Text(text.isEmpty ? title : text).font(chapterFont(.prose, skin: model.snapshot.appearance?.skin ?? "paper", size: 18)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .topLeading).padding().accessibilityIdentifier("entry.selectableText")
            }.modifier(ChapterScreenSurface()).navigationTitle("Select text").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(model.t("common.done")) { dismiss() } }
                ToolbarItem(placement: .primaryAction) { Button(copied ? model.t("common.copied") : model.t("common.copy")) { UIPasteboard.general.string = text; copied = true }.accessibilityIdentifier("entry.copyText") }
            }
        }
    }
}

/// Web Calendar Heatmap: one column per Monday-first UTC week, cells capped at 3.
struct WritingHeatmap: View {
    @EnvironmentObject private var model: VaultModel
    let counts: [Int]
    var body: some View {
        let preference = model.snapshot.appearance ?? .standard
        let colors = [chapterToken("line", preference: preference), chapterToken("accent-soft", preference: preference), chapterToken("accent", preference: preference).opacity(0.45), chapterToken("accent", preference: preference)]
        let weeks = counts.count / 7
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 3) {
                ForEach(0..<weeks, id: \.self) { week in
                    VStack(spacing: 3) {
                        ForEach(0..<7, id: \.self) { day in
                            RoundedRectangle(cornerRadius: 3).fill(colors[min(counts[week * 7 + day], 3)]).aspectRatio(1, contentMode: .fit)
                        }
                    }
                }
            }.accessibilityHidden(true)
            HStack {
                Text(model.tp("calendar.weeks", count: weeks))
                Spacer()
                Text(model.t("calendar.heatLess"))
                ForEach(0..<4, id: \.self) { i in RoundedRectangle(cornerRadius: 2.5).fill(colors[i]).frame(width: 9, height: 9).accessibilityHidden(true) }
                Text(model.t("calendar.heatMore"))
            }.font(chapterFont(.ui, skin: preference.skin, size: 11, relativeTo: .caption2)).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue("\(counts.filter { $0 > 0 }.count) / \(counts.count)")
        .accessibilityIdentifier("calendar.heatmap")
    }
}

/// Web Preferences "Your writing": six stats from state/stats.ts, counted on the device.
struct WritingStatsSection: View {
    @EnvironmentObject private var model: VaultModel
    var body: some View {
        let items = ChapterStats.items(model.entries)
        let now = Date().timeIntervalSince1970 * 1000
        // A @ViewBuilder body cannot mutate a local, so the UTC calendar is built in a closure.
        let utc: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }()
        let parts = utc.dateComponents([.year, .month], from: Date())
        let tiles: [(String, String, String)] = [
            ("entries", ChapterStats.compactCount(items.count), "prefs.stat.entries"),
            ("words", ChapterStats.compactCount(ChapterStats.totalWords(items)), "prefs.stat.words"),
            ("month", ChapterStats.compactCount(ChapterStats.monthWords(items, year: parts.year ?? 1970, month: (parts.month ?? 1) - 1)), "prefs.stat.month"),
            ("streak", String(ChapterStats.dayStreak(items, now: now)), "prefs.stat.streak"),
            ("longest", String(ChapterStats.longestStreak(items)), "prefs.stat.longest"),
            ("days", ChapterStats.compactCount(ChapterStats.journaledDays(items)), "prefs.stat.days"),
        ]
        let preference = model.snapshot.appearance ?? .standard
        Section {
            Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                ForEach(0..<3, id: \.self) { row in
                    GridRow {
                        ForEach(tiles[(row * 2)..<(row * 2 + 2)], id: \.0) { tile in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(tile.1).font(chapterFont(.heading, skin: preference.skin, size: 22, relativeTo: .title2)).foregroundStyle(chapterToken("ink", preference: preference))
                                Text(model.t(tile.2)).font(chapterFont(.ui, skin: preference.skin, size: 12, relativeTo: .caption)).foregroundStyle(chapterToken("ink", preference: preference))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading).padding(10)
                            .background(chapterToken("paper", preference: preference), in: RoundedRectangle(cornerRadius: 12))
                            .accessibilityElement(children: .combine).accessibilityIdentifier("stat." + tile.0)
                        }
                    }
                }
            }
            Text(model.t("prefs.writing.note")).font(.footnote)
        } header: { Text(model.t("prefs.writing.section")) }
    }
}

/// One grouped card of the connection screen: the inset-grouped Form look, without a lazy list.
private struct ConnectCard<Content: View>: View {
    @EnvironmentObject private var model: VaultModel
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .frame(maxWidth: .infinity, alignment: .leading).padding()
            .background(chapterToken("surface", preference: model.snapshot.appearance ?? .standard), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct ChapterTabs: View {
    @EnvironmentObject private var model: VaultModel
    var body: some View {
        TabView {
            EntryList().tabItem { Label("Journal", systemImage: "book") }
            CalendarView().tabItem { Label(model.t("shell.nav.calendar"), systemImage: "calendar") }
            NotebookList().tabItem { Label(model.t("shell.notebooks"), systemImage: "books.vertical") }
            SettingsView().tabItem { Label(model.t("common.settings"), systemImage: "gearshape") }
        }.font(chapterFont(.ui,skin:model.snapshot.appearance?.skin ?? "paper"))
        .onAppear { model.refreshBadges() }
        .onChange(of: model.snapshot) { model.refreshBadges() }
        .onChange(of: model.lastCompletePullID) { model.refreshBadges() }
        .sheet(item: Binding(get: { model.badgeQueue.first.map(BadgeID.init) }, set: { _ in })) { BadgeCelebrationView(id: $0.id) }
    }
}
struct EntryList: View {
    @EnvironmentObject private var model: VaultModel
    @State private var query = ""
    @State private var compose = false
    @State private var templating = false
    @State private var created: String?
    let journal: String?
    init(journal: String? = nil) { self.journal = journal }
    private var scoped: [VaultRecord] { model.entries.filter { journal == nil || $0.journalID == journal } }
    /// Web Search sheet results (search/core port): ranked title → label → date → content,
    /// with the matched field and a body snippet. An empty query keeps the full list.
    private var hits: [ChapterSearch.Hit]? {
        guard !ChapterSearch.normalize(query).isEmpty else { return nil }
        return ChapterSearch.searchHits(ChapterSearch.entries(scoped), query: query, locale: model.language?.id ?? "en")
    }
    var filtered: [VaultRecord] {
        guard let hits else { return scoped }
        let byID = Dictionary(scoped.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return hits.compactMap { byID[$0.id] }
    }
    private var notebook: VaultRecord? { model.journals.first { $0.journalID == journal } }
    @ViewBuilder var body: some View {
        // A pushed notebook already has the shelf's NavigationStack. A second
        // stack loses its native back path and makes the journal feel detached.
        if journal == nil { NavigationStack { content } } else { content }
    }
    private var content: some View {
        List {
            if let notebook {
                HStack(spacing: 14) {
                    NotebookCover(color:notebook.body["color"]?.string ?? "#B0563A",pattern:notebook.body["cover"]?.string ?? "plain")
                    VStack(alignment:.leading,spacing:4) {
                        if let subtitle=notebook.body["subtitle"]?.string,!subtitle.isEmpty { Text(subtitle).font(.subheadline) }
                        Text(chapterEntryCountLabel(model.entries.filter { $0.journalID == journal }.count)).font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(.vertical,8).listRowBackground(Color.clear).listRowSeparator(.hidden)
            }
            if filtered.isEmpty { Text(hits == nil ? "No downloaded entries. Sync or create your first entry." : model.t("shell.search.empty", ["query": query])).listRowBackground(Color.clear).accessibilityIdentifier("search.empty") }
            let found = Dictionary((hits ?? []).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            ForEach(filtered) { entry in
                NavigationLink { EntryDetail(entryID: entry.id) } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        ChapterEntryCard(entry:entry)
                        if let hit = found[entry.id] { SearchHitDetail(hit: hit) }
                    }
                }
                    .listRowBackground(Color.clear).listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top:6,leading:16,bottom:6,trailing:16))
            }
        }.listStyle(.plain)
        .modifier(ChapterScreenSurface()).navigationTitle(notebook?.title ?? "Journal")
        .searchable(text:$query,prompt:model.t("shell.search.placeholder"))
        .refreshable { await model.sync() }
        .toolbar {
            ToolbarItem(placement:.topBarTrailing) { Button { compose=true } label: { Label(model.t("shell.newEntry"),systemImage:"square.and.pencil") } }
            if !model.journals.isEmpty {
                ToolbarItem(placement:.topBarTrailing) { Button { templating=true } label: { Label("New from template",systemImage:"doc.on.doc") }.accessibilityIdentifier("journal.fromTemplate") }
            }
        }
        .sheet(isPresented:$compose) { EntryEditor(journal:journal ?? model.journals.first?.journalID ?? "default") }
        .sheet(isPresented:$templating) { TemplatePicker(journal:journal ?? model.journals.first?.journalID ?? "") { created = $0 } }
        .navigationDestination(item:$created) { EntryDetail(entryID:$0) }
    }
}

/// Original JournalEntries/Calendar card: 14pt radius, original --surface/line,
/// notebook-colored 3pt leading edge, original heading/UI/mono roles. Native
/// NavigationLink, Dynamic Type, selection and RTL remain real iOS behavior.
private func chapterEntryCountLabel(_ count:Int) -> String {
    count == 1 ? "1 entry" : "\(count) entries"
}

struct ChapterEntryCard: View {
    @EnvironmentObject private var model: VaultModel
    let entry: VaultRecord
    private var preference: SharedAppearance { model.snapshot.appearance ?? .standard }
    private var notebookColor: Color {
        if let color=model.journals.first(where:{$0.journalID == entry.journalID})?.body["color"]?.string { return Color(chapterHex:color) }
        return chapterToken("ink-3",preference:preference)
    }
    var body: some View {
        VStack(alignment:.leading,spacing:5) {
            Text(entry.title).font(chapterFont(.heading,skin:preference.skin,size:20,relativeTo:.headline))
                .foregroundStyle(chapterToken("ink",preference:preference))
            if !entry.text.isEmpty {
                Text(entry.text).font(chapterFont(.ui,skin:preference.skin,size:15,relativeTo:.subheadline))
                    .foregroundStyle(chapterToken("ink-2",preference:preference)).lineLimit(2)
            }
            Text(entry.date,format:.dateTime.month().day().year())
                .font(chapterFont(.mono,skin:preference.skin,size:12,relativeTo:.caption))
                .foregroundStyle(chapterToken("ink-2",preference:preference))
        }.frame(maxWidth:.infinity,alignment:.leading).padding(14)
        .background(chapterToken("surface",preference:preference))
        .overlay { RoundedRectangle(cornerRadius:14).strokeBorder(chapterToken("line",preference:preference),lineWidth:1) }
        .overlay(alignment:.leading) { Rectangle().fill(notebookColor).frame(width:3) }
        .clipShape(RoundedRectangle(cornerRadius:14))
        .accessibilityElement(children:.contain).accessibilityIdentifier("entry.card."+entry.id)
    }
}

struct EntryDetail: View {
    @EnvironmentObject private var model: VaultModel
    let entryID: String
    @State private var importSession: UUID?
    @State private var importingFile = false
    @State private var importingMedia = false
    @State private var photoSelection: PhotosPickerItem?
    @State private var editing = false
    @State private var editRich = false
    @State private var moving = false
    @State private var deleting = false
    @State private var deletionExpected: VaultRecord?
    @State private var editingMetadata = false
    @State private var linking = false
    @State private var showingActions = false
    @State private var showingPlainEdit = false
    @State private var selectingText = false
    @State private var previewURL: URL?
    @State private var loadingMedia: String?
    @State private var mediaError: String?
    @Environment(\.dismiss) private var dismiss
    var entry: VaultRecord? { model.entries.first { $0.id.utf8.elementsEqual(entryID.utf8) } }
    var body: some View {
        Group {
            if let entry {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Spacer()
                            Button("More") { showingActions.toggle() }.accessibilityValue(showingActions ? "Expanded":"Collapsed").frame(minWidth:44,minHeight:44).buttonStyle(.bordered)
                        }
                        if showingActions {
                            VStack(alignment:.leading) {
                                Button("Title, date and labels") { showingActions = false; editingMetadata = true }.frame(minHeight:44)
                                Button(model.t("journals.picker.heading")) { showingActions = false; moving = true }.frame(minHeight:44).disabled(model.journals.isEmpty)
                                Button("Select text") { showingActions = false; selectingText = true }.frame(minHeight:44).accessibilityIdentifier("entry.selectText")
                                Button("Link to another entry") { showingActions = false; linking = true }.frame(minHeight:44)
                                    .disabled(entry.body["bodyJson"]?.string.flatMap({ try? RichDocument(json: $0) }) == nil).accessibilityIdentifier("entry.addLink")
                                Button(model.t("editor.delete.confirmLabel"),role:.destructive) { showingActions = false; deletionExpected = entry; deleting = true }.frame(minHeight:44)
                            }
                        }
                        if showingPlainEdit {
                            VStack(alignment:.leading) {
                                Button("Text and details") { showingPlainEdit = false; editRich = false; editing = true }.frame(minHeight:44)
                                Button("Rich document") { showingPlainEdit = false; editRich = true; editing = true }.frame(minHeight:44)
                            }
                        }
                        Text(entry.title).font(chapterFont(.heading,skin:model.snapshot.appearance?.skin ?? "paper",size:34,relativeTo:.largeTitle)).accessibilityAddTraits(.isHeader).accessibilityIdentifier("entry.title")
                        Text(entry.date, style: .date).foregroundStyle(.secondary)
                        if let notebook = model.journals.first(where: { $0.journalID == entry.journalID }) { Text("Notebook: " + notebook.title).font(.footnote).accessibilityIdentifier("entry.notebook") }
                        if let raw = entry.body["bodyJson"]?.string, let document = try? RichDocument(json: raw) {
                            RichDocumentView(entry: entry, document: document)
                        } else { Text(entry.text).font(chapterFont(.prose,skin:model.snapshot.appearance?.skin ?? "paper",size:18)) }
                        let links=entry.uniqueLinkedEntryIDs
                        if !links.isEmpty {
                            Text("Linked entries").font(.headline).accessibilityAddTraits(.isHeader)
                            ForEach(Array(links.enumerated()),id:\.offset) { _,id in
                                NavigationLink {LinkedEntryDestination(entryID:id)} label: {
                                    Label(model.entries.first(where:{$0.id.utf8.elementsEqual(id.utf8)})?.title ?? "Linked entry — not downloaded",systemImage:"link").frame(minHeight:44)
                                }.accessibilityIdentifier("entry.link."+id)
                            }
                        }
                        let backlinks=model.snapshot.backlinks(to:entry.id)
                        if !backlinks.isEmpty {
                            Text(model.t("editor.linkedFrom")).font(.headline).accessibilityAddTraits(.isHeader)
                            ForEach(backlinks) {source in
                                NavigationLink {EntryDetail(entryID:source.id)} label:{Label(source.title,systemImage:"arrow.uturn.backward").frame(minHeight:44)}
                                    .accessibilityIdentifier("entry.backlink."+source.id)
                            }
                        }
                        let labels = entry.labels
                        if !labels.isEmpty { Text(labels.joined(separator: " · ")).font(.caption).accessibilityIdentifier("entry.labels") }
                        ForEach(entry.mediaReferences) { media in
                            Button {
                                loadingMedia = media.id; mediaError = nil
                                Task {
                                    do { previewURL = try await model.downloadMedia(media) }
                                    catch { mediaError = error.localizedDescription }
                                    loadingMedia = nil
                                }
                            } label: {
                                if loadingMedia == media.id { ProgressView("Decrypting attachment") }
                                else { Label("Preview \(media.name)", systemImage: "paperclip") }
                            }.disabled(loadingMedia != nil).accessibilityIdentifier("media.preview." + media.id)
                        }
                        if model.canImportMedia, entry.body["bodyJson"]?.string != nil {
                            Button { importSession = model.mediaSession; importingFile = true } label: { Label("Attach file", systemImage: "doc.badge.plus") }
                                .disabled(importingMedia).accessibilityHint("Files up to 128 MiB; saved encrypted before sync")
                            PhotosPicker(selection: $photoSelection, matching: .images) { Label("Attach photo", systemImage: "photo.badge.plus") }.disabled(importingMedia)
                            if importingMedia { ProgressView("Encrypting attachment") }
                            if !(model.snapshot.mediaUploads ?? []).isEmpty { Text("Attachments waiting to upload: \(model.snapshot.mediaUploads?.count ?? 0). Their entry references are not sent until upload completes.").font(.footnote) }
                        }
                        if let mediaError { Text(mediaError).font(.footnote).foregroundStyle(.red).accessibilityIdentifier("media.error") }
                        if !entry.editablePlainText { Text("Rich structure is preserved. Native editing supports formatted runs, formatting a selection, adding and arranging whole blocks, simple table editing, and inserting links or templates at the cursor. Restructuring inside a block and custom-node editing remain incomplete.").font(.footnote).foregroundStyle(.secondary) }
                    }.padding().frame(maxWidth: .infinity, alignment: .leading)
                }
                .toolbar {
                    if entry.editablePlainText {
                        Button(model.t("common.edit")) { showingPlainEdit.toggle() }.accessibilityValue(showingPlainEdit ? "Expanded":"Collapsed")
                    } else if entry.body["bodyJson"]?.string.flatMap({ try? RichDocument(json: $0) }) != nil { Button(model.t("common.edit")) { editRich = true; editing = true } }

                }
                .sheet(isPresented: $editing) {
                    if entry.editablePlainText && !editRich { EntryEditor(existing: entry, journal: entry.journalID) }
                    else if let raw = entry.body["bodyJson"]?.string, (try? RichDocument(json: raw)) != nil { RichEntryEditor(entry: entry) }
                }
                .sheet(isPresented: $moving) { MoveEntryView(entry: entry) }
                .sheet(isPresented: $selectingText) { SelectableEntryText(title: entry.title, text: entry.text) }
                .sheet(isPresented: $linking) { EntryLinkPicker(entry: entry) }
                .sheet(isPresented: $editingMetadata) { EntryMetadataEditor(entry: entry) }
                .confirmationDialog("Delete this entry on all synced devices?", isPresented: $deleting, titleVisibility: .visible) {
                    Button(model.t("editor.delete.confirmLabel"), role: .destructive) { do { guard let deletionExpected else { throw ChapterError.conflict }; try model.deleteEntry(deletionExpected); dismiss() } catch { model.message = error.localizedDescription } }
                } message: { Text("An encrypted recovery copy remains in Settings. Pending writing, rich drafts and attachment uploads are retained. This is not secure erasure; notebook/media purge is not implemented.") }
            } else { Text("This entry is no longer available.") }
        }.modifier(ChapterScreenSurface()).navigationTitle("Entry").navigationBarTitleDisplayMode(.inline).quickLookPreview($previewURL)
        .onChange(of: previewURL) { old, new in if new == nil, let old { model.discardPlayback(old) } }
        .fileImporter(isPresented: $importingFile, allowedContentTypes: [.data]) { result in
            guard let entry, let session = importSession else { return }
            switch result {
            case .failure(let error): mediaError = error.localizedDescription
            case .success(let url):
                importingMedia = true; mediaError = nil
                Task {
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() }; importingMedia = false }
                    do { try await model.importMedia(source: url, name: url.lastPathComponent, mime: UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream", entry: entry, session: session) }
                    catch { mediaError = error.localizedDescription }
                }
            }
        }
        .onChange(of: photoSelection) { _, selected in
            guard let selected, let entry else { return }
            let session = model.mediaSession
            importingMedia = true; mediaError = nil
            Task {
                defer { importingMedia = false; photoSelection = nil }
                do {
                    guard let imported = try await selected.loadTransferable(type: PrivateImportedFile.self) else { throw ChapterError.unsupported }
                    defer { try? FileManager.default.removeItem(at: imported.url.deletingLastPathComponent()) }
                    try await model.importMedia(source: imported.url, name: "Photo." + imported.url.pathExtension, mime: selected.supportedContentTypes.compactMap(\.preferredMIMEType).first ?? UTType(filenameExtension: imported.url.pathExtension)?.preferredMIMEType ?? "application/octet-stream", entry: entry, session: session)
                } catch { mediaError = error.localizedDescription }
            }
        }
    }
}
struct EntryEditor: View {
    @EnvironmentObject private var model: VaultModel
    @Environment(\.dismiss) private var dismiss
    @State private var draft: PlainEntryDraft
    @State private var error: String?
    @State private var recoverySaved = false
    @State private var copying = false
    init(existing: VaultRecord? = nil, journal: String) {
        _draft = State(initialValue: PlainEntryDraft(existing: existing, journal: journal))
    }
    init(recovery: PlainEntryDraft) {
        _draft = State(initialValue: recovery); _recoverySaved = State(initialValue: true)
    }
    private func save(asNew: Bool = false) {
        recoverySaved = false
        do {
            draft = try model.keepPlainDraft(draft); recoverySaved = true
            let record = try model.applyPlainDraft(draft, asNew: asNew)
            draft.expected = record; draft.revision = 0
            recoverySaved = false; error = nil
            if asNew { dismiss() }
        } catch ChapterError.conflict { self.error = "The entry, notebook or recovery draft changed elsewhere. Your original was not overwritten."
        } catch { self.error = error.localizedDescription }
    }
    var body: some View {
        NavigationStack {
            Form {
                TextField("Title", text: $draft.title).accessibilityLabel("Entry title")
                DatePicker("Entry date", selection: $draft.date)
                if draft.expected == nil { TextField("Labels, separated by commas", text: $draft.labels) }
                else {
                    LabeledContent("Labels",value:draft.labels)
                    Text("Labels are preserved while writing. Use the entry’s More → Title, date and labels form to edit individual labels, including labels containing commas.").font(.footnote)
                }
                Picker(model.t("shell.compose.notebook"), selection: $draft.journal) {
                    if draft.journal == "default" || model.journals.isEmpty { Text("Journal").tag("default") }
                    if draft.journal != "default" && !model.journals.contains(where: { $0.journalID == draft.journal }) { Text("Unavailable notebook — choose another").tag(draft.journal) }
                    ForEach(model.journals) { Text($0.title).tag($0.journalID) }
                }
                Section("Writing") { TextEditor(text: $draft.text).font(chapterFont(.prose,skin:model.snapshot.appearance?.skin ?? "paper",size:18)).frame(minHeight: 260).accessibilityLabel("Journal text") }
                if let error {
                    Section("Unsaved changes") {
                        Text(error).foregroundStyle(.red)
                        Text(recoverySaved ? "Draft saved encrypted on this device. The original entry was not overwritten. Close and resume it from Settings, retry, or save your writing as a new entry." : "The latest typing could not be saved. Keep this screen open and retry; do not close or uninstall the app.").accessibilityIdentifier("writing.recovery-status")
                        if !recoverySaved {
                            Button("Keep separate recovery draft") {
                                do { draft = try model.keepPlainDraft(draft.separateRecovery()); recoverySaved = true }
                                catch { self.error = error.localizedDescription }
                            }
                        }
                        Button("Retry save") { save() }
                        Button("Save as new entry") { copying = true }.disabled(!recoverySaved)
                    }
                } else { Text(recoverySaved ? "Recovered writing is saved encrypted on this device. Tap Done to apply it." : draft.expected == nil ? "Start writing to save an encrypted draft." : "Saved encrypted on this device.").font(.footnote) }
            }.modifier(ChapterScreenSurface()).navigationTitle(draft.expected == nil ? model.t("editor.newEntry") : "Edit entry")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(model.t("common.close")) { dismiss() }.disabled(error != nil && !recoverySaved).accessibilityIdentifier("writing.close") }
                ToolbarItem(placement: .confirmationAction) { Button(model.t("common.done")) { save(); if error == nil { dismiss() } } }
            }
            .onChange(of: draft.title) { _, _ in save() }.onChange(of: draft.text) { _, _ in save() }
            .onChange(of: draft.labels) { _, _ in save() }.onChange(of: draft.date) { _, _ in save() }
            .onChange(of: draft.journal) { _, _ in save() }
            .interactiveDismissDisabled(error != nil && !recoverySaved)
            .confirmationDialog("Save this writing as a new entry?", isPresented: $copying, titleVisibility: .visible) {
                Button("Save new text entry") { save(asNew: true) }
                Button(model.t("common.cancel"), role: .cancel) {}
            } message: { Text("The original entry and attachments remain unchanged. This creates a separate text entry with your title, date, labels and selected notebook; attachments are not duplicated.") }
        }
    }
}
/// Explicit-save native metadata form. Rich JSON and media never pass through a text editor.
struct EntryMetadataEditor: View {
    @EnvironmentObject private var model: VaultModel
    @Environment(\.dismiss) private var dismiss
    @State private var expected: VaultRecord
    @State private var title: String
    @State private var date: Date
    @State private var labels: [MetadataLabel]
    @State private var newLabel = ""
    @State private var error: String?
    @State private var discarding = false
    private struct MetadataLabel: Identifiable { let id = UUID(); let text: String }
    init(entry: VaultRecord) {
        _expected = State(initialValue: entry); _title = State(initialValue: entry.title)
        _date = State(initialValue: entry.date)
        _labels = State(initialValue: (entry.editableEntryLabels ?? []).map { MetadataLabel(text:$0) })
    }
    private var candidate: String { EntryLabels.normalized(newLabel) }
    private var values: [String] { labels.map(\.text) }
    private var hasChanges: Bool { !title.utf8.elementsEqual(expected.title.utf8) || date != expected.date || !EntryLabels.sameValues(values,expected.editableEntryLabels ?? []) || !candidate.isEmpty }
    private var suggestions: [String] {
        EntryLabels.unique(model.entries.flatMap(\.labels)).sorted().filter { !EntryLabels.contains(values,$0) && (candidate.isEmpty || $0.contains(candidate)) }.prefix(8).map { $0 }
    }
    private func add(_ value: String) { if !value.isEmpty && !EntryLabels.contains(values,value) { labels.append(MetadataLabel(text:value)) }; newLabel = "" }
    private func save() {
        do {
            var finalLabels = values
            if !candidate.isEmpty && !EntryLabels.contains(finalLabels,candidate) { finalLabels.append(candidate) }
            try model.updateEntryMetadata(expected, title:title.utf8.elementsEqual(expected.title.utf8) ? nil:title, date:date == expected.date ? nil:date, labels:expected.editableEntryLabels == nil || EntryLabels.sameValues(finalLabels,expected.editableEntryLabels ?? []) ? nil:finalLabels)
            dismiss()
        } catch { self.error = "Not saved. Your original entry was not changed. " + error.localizedDescription }
    }
    var body: some View {
        NavigationStack {
            Form {
                Text("Tap Save to apply metadata. Original rich content, attachments and other fields stay intact. Unsaved form changes are not autosaved; save before leaving or locking the app.").font(.footnote)
                TextField("Title",text:$title).accessibilityIdentifier("metadata.title")
                DatePicker(model.t("editor.date.heading"),selection:$date).accessibilityIdentifier("metadata.date")
                Section("Labels") {
                    if expected.editableEntryLabels != nil {
                        ForEach(labels) { label in
                            HStack { Text(label.text); Spacer(); Button { labels.removeAll { $0.id == label.id } } label: { Image(systemName:"xmark.circle") }.buttonStyle(.borderless).frame(minWidth:44,minHeight:44).accessibilityLabel("Remove label " + label.text) }
                        }
                        TextField("New label",text:$newLabel).textInputAutocapitalization(.never).autocorrectionDisabled().onSubmit { add(candidate) }.accessibilityIdentifier("metadata.new-label")
                        Button("Add label") { add(candidate) }.disabled(candidate.isEmpty || EntryLabels.contains(values,candidate))
                        ForEach(suggestions,id:\.self) { value in Button("Use label " + value) { add(value) } }
                    } else { Text("These labels use a newer format. They are preserved unchanged; title/date editing is still available.") }
                }
                if let error { Text(error).foregroundStyle(.red).accessibilityIdentifier("metadata.error") }
            }.modifier(ChapterScreenSurface()).navigationTitle("Entry details")
            .toolbar {
                ToolbarItem(placement:.cancellationAction) { Button(model.t("common.cancel")) { if hasChanges { discarding = true } else { dismiss() } } }
                ToolbarItem(placement:.confirmationAction) { Button(model.t("common.save")) { save() } }
            }.interactiveDismissDisabled(hasChanges)
            .confirmationDialog("Discard unsaved metadata changes?",isPresented:$discarding,titleVisibility:.visible) {
                Button("Discard changes",role:.destructive) { dismiss() }; Button("Keep editing",role:.cancel) {}
            }
        }
    }
}
struct NotebookList: View {
    @EnvironmentObject private var model: VaultModel
    @State private var created: String?
    @State private var adding = false
    @State private var editing: VaultRecord?
    var body: some View {
        NavigationStack {
            List { ForEach(model.journals) { journal in
                HStack {
                    NavigationLink { EntryList(journal: journal.journalID) } label: {
                        HStack(spacing: 14) {
                            NotebookCover(color:journal.body["color"]?.string ?? "#B0563A",pattern:journal.body["cover"]?.string ?? "plain")
                            VStack(alignment: .leading, spacing:4) { Text(journal.title).font(chapterFont(.heading,skin:model.snapshot.appearance?.skin ?? "paper",size:22,relativeTo:.title2))
                                if let subtitle = journal.body["subtitle"]?.string, !subtitle.isEmpty { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
                                Text(chapterEntryCountLabel(model.entries.filter { $0.journalID == journal.journalID }.count)).font(.caption).foregroundStyle(.secondary)
                            }
                        }.padding(.vertical,6)
                    }
                    Button { editing = journal } label: { Image(systemName: "pencil").frame(minWidth: 44, minHeight: 44) }
                        .buttonStyle(.borderless).accessibilityLabel("Edit notebook " + journal.title)
                }.listRowBackground(chapterToken("surface",preference:model.snapshot.appearance ?? .standard))
            } }
                .sheet(item: $editing) { NotebookEditor(journal: $0) }
                .modifier(ChapterScreenSurface()).navigationTitle(model.t("shell.notebooks")).toolbar { Button { adding = true } label: { Label(model.t("journals.new"), systemImage: "plus") }.accessibilityIdentifier("notebook.new") }
                .sheet(isPresented: $adding) { NewNotebookSheet { created = $0 } }
                .navigationDestination(item: $created) { EntryDetail(entryID: $0) }
        }
    }
}
struct NotebookEditor: View {
    @EnvironmentObject private var model: VaultModel
    @Environment(\.dismiss) private var dismiss
    let journal: VaultRecord
    @State private var name: String
    @State private var subtitle: String
    @State private var color: String
    @State private var cover: String
    @State private var error: String?
    @State private var deletionPlan: NotebookDeletionPlan?
    @State private var deletionCompleted = false
    private var hasMetadataEdits: Bool {
        name != (journal.body["name"]?.string ?? journal.title) || subtitle != (journal.body["subtitle"]?.string ?? "") || color != (journal.body["color"]?.string ?? "") || cover != (journal.body["cover"]?.string ?? "plain")
    }
    private let covers = ["lines", "dots", "grid", "plain", "photo"]
    init(journal: VaultRecord) {
        self.journal = journal
        _name = State(initialValue: journal.body["name"]?.string ?? journal.title)
        _subtitle = State(initialValue: journal.body["subtitle"]?.string ?? "")
        _color = State(initialValue: journal.body["color"]?.string ?? "")
        _cover = State(initialValue: journal.body["cover"]?.string ?? "plain")
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        NotebookCover(color: color.isEmpty ? JournalColorSwatches.colors[0] : color, pattern: cover).accessibilityHidden(true)
                        TextField(model.t("journals.name.placeholder"), text: $name).accessibilityIdentifier("notebook.name")
                    }
                    TextField(model.t("journals.field.subtitle"), text: $subtitle, axis: .vertical).accessibilityIdentifier("notebook.subtitle")
                }
                Section(model.t("journals.field.colour")) { JournalColorSwatches(color: $color) }
                Section {
                    Picker(model.t("journals.field.cover"), selection: $cover) {
                        ForEach(covers, id: \.self) { Text(model.t("journals.cover." + $0)).tag($0) }
                        if !covers.contains(cover) { Text("Existing: " + cover).tag(cover) }
                    }.accessibilityIdentifier("notebook.cover")
                    Text("These settings sync to the original web client. The notebook cover retains its original web pattern. Photo preserves the original cover style; this does not upload a cover image.").font(.footnote)
                }
                Section("Recoverable deletion") {
                    Button("Delete notebook and downloaded entries",role:.destructive) {
                        do { deletionPlan = try model.prepareNotebookDeletion(journal) } catch { self.error = "Unable to prepare deletion. Reopen after changes finish. " + error.localizedDescription }
                    }.disabled(hasMetadataEdits || model.syncing).accessibilityIdentifier("notebook.delete.prepare")
                    Text("Save or cancel notebook detail edits first. Deletion retains an encrypted local recovery, drafts and media; it is not secure erasure. Review the downloaded entry list before confirming.").font(.footnote)
                }
                if let error { Section { Text(error).accessibilityIdentifier("notebook.error") } }
            }.modifier(ChapterScreenSurface()).navigationTitle(model.t("journals.edit.title"))
                .sheet(item:$deletionPlan,onDismiss:{ if deletionCompleted { dismiss() } }) { plan in
                    NotebookDeletionView(plan:plan,onDeleted:{deletionCompleted = true})
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button(model.t("common.cancel")) { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        // Web EditJournalSheet: name.trim() || t('journals.untitled'), subtitle.trim().
                        Button(model.t("journals.saveChanges")) { do { let n = name.trimmingCharacters(in: .whitespacesAndNewlines); try model.updateJournal(journal, name: n.isEmpty ? model.t("journals.untitled") : n, subtitle: subtitle.trimmingCharacters(in: .whitespacesAndNewlines), color: color, cover: cover); dismiss() } catch { self.error = "Unable to save: " + error.localizedDescription + " Your edits are retained here. Cancel and reopen if this notebook changed on another device." } }
                    }
                }
        }
    }
}
struct CalendarView: View {
    @EnvironmentObject private var model: VaultModel
    @State private var day = Date()
    var body: some View {
        NavigationStack {
            List {
                DatePicker("Date", selection: $day, displayedComponents: .date).datePickerStyle(.graphical)
                let dayEntries = model.entries.filter { Calendar.current.isDate($0.date, inSameDayAs: day) }
                Section("Entries on this day") {
                    ForEach(dayEntries) { entry in
                        NavigationLink { EntryDetail(entryID:entry.id) } label: { ChapterEntryCard(entry:entry) }
                            .listRowBackground(Color.clear).listRowSeparator(.hidden)
                    }
                    if dayEntries.isEmpty { Text(model.t("calendar.empty.day")).accessibilityIdentifier("calendar.emptyDay") }
                }
                // Web OnThisDay: the same UTC month/day in earlier years, newest first, at most 3.
                let parts = Calendar.current.dateComponents([.year, .month, .day], from: day)
                let memories = ChapterStats.onThisDay(ChapterStats.items(model.entries), month: (parts.month ?? 1) - 1, day: parts.day ?? 1, year: parts.year ?? 1970).prefix(3)
                if !memories.isEmpty {
                    Section(model.t("calendar.onThisDay")) {
                        ForEach(Array(memories), id: \.id) { item in
                            if let entry = model.entries.first(where: { $0.id == item.id }) {
                                NavigationLink { EntryDetail(entryID: entry.id) } label: {
                                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                                        Text(String(ChapterStats.utcParts(item.createdAt).year ?? 0)).font(chapterFont(.mono, skin: model.snapshot.appearance?.skin ?? "paper", size: 12, relativeTo: .caption))
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(entry.title).font(chapterFont(.heading, skin: model.snapshot.appearance?.skin ?? "paper", size: 15, relativeTo: .body))
                                            Text(item.bodyText).font(.footnote).lineLimit(1)
                                        }
                                    }.frame(minHeight: 44)
                                }.accessibilityIdentifier("calendar.memory." + entry.id)
                            }
                        }
                    }
                }
                Section { WritingHeatmap(counts: ChapterStats.dailyCounts(ChapterStats.items(model.entries), now: Date().timeIntervalSince1970 * 1000, weeks: 17)) }
                Section("On this device") { LabeledContent(model.t("prefs.stat.entries"), value: "\(model.entries.count)")
                    // Web journaledDays: distinct UTC days, the calendar grid's boundaries.
                    LabeledContent(model.t("prefs.stat.days"), value: "\(ChapterStats.journaledDays(ChapterStats.items(model.entries)))") }
            }.modifier(ChapterScreenSurface()).navigationTitle(model.t("shell.nav.calendar"))
        }
    }
}
struct SettingsView: View {
    @EnvironmentObject private var model: VaultModel
    @State private var managingInterviews = false
    @State private var exporting = false
    @State private var importingDayOne = false
    var body: some View {
        NavigationStack {
            Form {
                AppearanceSettings()
                if let catalog = ChapterLocales.bundled {
                    Section(model.t("prefs.language")) {
                        Picker(model.t("prefs.language"), selection: Binding(get: { model.language?.id ?? "en" }, set: { model.setLanguage($0) })) {
                            ForEach(catalog.locales) { Text($0.name).tag($0.id) }
                        }.accessibilityIdentifier("settings.language")
                        Text("Device-only, like the web app, and never synced. Built-in templates, dates, layout direction and the screens already using the web app’s own translations follow it; the rest of the native text is still English.").font(.footnote)
                    }
                }
                WritingStatsSection()
                BadgeGallerySection()
                Section("Your data") {
                    Button { exporting = true } label: { Label(model.t("vault.export.title"), systemImage: "square.and.arrow.up") }
                        .frame(minHeight: 44).accessibilityIdentifier("settings.export")
                    Button { importingDayOne = true } label: { Label(model.t("prefs.vault.import"), systemImage: "square.and.arrow.down") }
                        .frame(minHeight: 44).accessibilityIdentifier("settings.import")
                }
                Section(model.t("prefs.assistant.section")) {
                    Button { managingInterviews = true } label: { Label(model.t("prefs.assistant.interviewTypes"), systemImage: "list.bullet") }
                        .frame(minHeight: 44).accessibilityIdentifier("settings.interviewTypes")
                }
                Section("Sync") {
                    Button { Task { await model.sync() } } label: { if model.syncing { ProgressView("Syncing") } else { Label("Sync now", systemImage: "arrow.triangle.2.circlepath") } }.disabled(model.syncing)
                    LabeledContent("Pending changes", value: "\(model.pending)")
                    if let message = model.message { Text(message).font(.footnote) }
                }
                if !model.snapshot.conflicts.isEmpty {
                    Section("Recovered conflicts") {
                        Text("Divergent versions and failed writing drafts remain encrypted here. Resume writing or restore an entry copy; nothing is automatically discarded.").font(.footnote)
                        ForEach(Array(model.snapshot.conflicts.enumerated()), id: \.offset) { _, record in
                            VStack(alignment: .leading) { Text(record.title).font(.headline); Text(record.text).lineLimit(4)
                                if record.kind == PlainEntryDraft.recoveryKind, let draft = try? PlainEntryDraft(recovery:record) {
                                    NavigationLink("Resume unsaved writing") { EntryEditor(recovery:draft) }
                                } else if record.kind == NotebookDeletionRecovery.recoveryKind, let recovery = try? NotebookDeletionRecovery(recovery:record) {
                                    if recovery.restored { Text("Notebook and original entries were restored. Encrypted history remains retained.").font(.footnote) }
                                    else {
                                        Text("Restores the original notebook and its " + String(recovery.plan.entries.count) + " entries only if their deletion checkpoints are unchanged. Media and drafts remain retained.").font(.footnote)
                                        Button("Restore notebook and entries") { do { try model.restoreNotebookDeletion(record) } catch { model.message = "Notebook restore refused; existing records/recovery are unchanged. " + error.localizedDescription } }.disabled(model.syncing)
                                    }
                                } else if record.kind == "entry" {
                                    Button("Restore as new entry") { do { try model.restoreConflict(record) } catch { model.message = error.localizedDescription } }
                                } else if record.kind == "aiSettings", let preference=try? SharedAppearance(value:record.body["settings"]?["chapterAppearance"] ?? .null) {
                                    Text("Recovered appearance: " + preference.skin + ", " + preference.palette + ", " + preference.mode).font(.footnote)
                                    Button("Apply recovered appearance") { do { try model.saveAppearance(preference) } catch { model.message=error.localizedDescription } }
                                    Text("Only appearance is reapplied over current settings; current AI credentials and both recovered versions remain preserved.").font(.footnote)
                                } else {
                                    Text("This metadata conflict is preserved read-only; restoring it needs kind-specific handling.").font(.footnote)
                                }
                            }
                        }
                    }
                }
                if let drafts = model.snapshot.richDrafts, !drafts.isEmpty {
                    Section("Encrypted rich-text drafts") {
                        ForEach(drafts) { draft in
                            NavigationLink { RichDraftEditor(draft: draft) } label: { Text(draft.text.isEmpty ? "Empty text-run draft" : draft.text).lineLimit(2) }
                        }
                    }
                }
                if let uploads = model.snapshot.mediaUploads, !uploads.isEmpty {
                    Section("Encrypted attachment outbox") {
                        ForEach(uploads) { upload in
                            VStack(alignment: .leading) {
                                Text(upload.name)
                                Text(model.mediaErrors[upload.id] ?? "Waiting to upload. Local encrypted chunks are retained.").font(.footnote)
                            }
                        }
                        Button("Retry attachments and sync") { Task { await model.sync() } }.disabled(model.syncing)
                    }
                }
                Section("Privacy") {
                    Text("No analytics, ads, cloud account, remote previews or automatic AI requests. Offline records are AES-GCM encrypted with a device-only Keychain key; sync uses the existing XChaCha20 vault protocol. Recovery phrase and sessions are memory-only.")
                    Text("The app locks on background. The phrase is required again to unlock; local-key access may request device authentication. Unsynced drafts remain encrypted on this device.")
                    Button("Lock vault", role: .destructive) { model.lock() }
                }
                Section("Not yet implemented") {
                    Text("Typing across several runs at once (each run is edited separately; formatting can span runs), exact custom media/interview card rendering, editing tables with merged cells, camera/audio/video capture, large media and unsupported playback codecs, interviews, AI and transcription, maps, reminders, translating every screen (some text is still English), vault deletion/rotation and operator tools. The web app remains available for these. This preview is not full parity or an independently audited secure product.")
                }
                Section("Open source") { NavigationLink("Original font licenses") { ChapterFontLicenses() }; Link("Source and AGPL-3.0 license", destination: URL(string: "https://github.com/BubbyWoodz/Chapter")!) }
            }.modifier(ChapterScreenSurface()).navigationTitle(model.t("common.settings"))
            .sheet(isPresented: $managingInterviews) { InterviewTypesView() }
            .sheet(isPresented: $exporting) { ExportJournalView() }
            .sheet(isPresented: $importingDayOne) { ImportDayOneView() }
        }
    }
}

/// PhotosPicker grants access only to selected content. Copy its temporary file
/// in bounded chunks into a protected, backup-excluded transient directory.
struct PrivateImportedFile: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .data) { received in
            let size = try received.file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? -1
            guard (0...MediaLimits.maximumPlainBytes).contains(size) else { throw ChapterError.unsupported }
            let root = try EncryptedSnapshotStore.applicationDirectory().appendingPathComponent("ImportStaging", isDirectory: true).appendingPathComponent(UUID().uuidString, isDirectory: true)
            try EncryptedMediaFiles.protectedDirectory(root)
            var success = false
            defer { if !success { try? FileManager.default.removeItem(at: root) } }
            let ext = received.file.pathExtension
            let safeExtension = ext.utf8.count <= 12 && ext.utf8.allSatisfy { (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) } ? ext : "bin"
            let destination = root.appendingPathComponent("selected").appendingPathExtension(safeExtension)
            guard FileManager.default.createFile(atPath: destination.path, contents: nil, attributes: [.protectionKey: FileProtectionType.complete]) else { throw ChapterError.storage }
            let input = try FileHandle(forReadingFrom: received.file), output = try FileHandle(forWritingTo: destination)
            defer { try? input.close(); try? output.close() }
            var bytes = 0
            while let data = try input.read(upToCount: MediaLimits.chunkBytes), !data.isEmpty {
                try Task.checkCancellation()
                guard bytes <= MediaLimits.maximumPlainBytes - data.count else { throw ChapterError.unsupported }
                try output.write(contentsOf: data); bytes += data.count
            }
            guard bytes == size else { throw ChapterError.corruptData }
            try output.synchronize(); success = true
            return PrivateImportedFile(url: destination)
        }
    }
}

// The catalog is generated from original web tokens, not approximate system colors.
private extension Color {
    init(chapterHex: String) {
        let value=UInt64(chapterHex.trimmingCharacters(in:CharacterSet(charactersIn:"#")),radix:16) ?? 0xB0563A
        self.init(.sRGB,red:Double((value>>16)&255)/255,green:Double((value>>8)&255)/255,blue:Double(value&255)/255,opacity:1)
    }
}
/// Original web language effects: Arabic flips the layout to right-to-left
/// (<html dir="rtl">) and dates follow the chosen language. English leaves
/// the device's own regional formatting untouched.
private struct ChapterLanguageStyle: ViewModifier {
    let language: ChapterLocale?
    @ViewBuilder func body(content: Content) -> some View {
        if let language, language.id != "en" {
            content.environment(\.layoutDirection, language.isRightToLeft ? .rightToLeft : .leftToRight).environment(\.locale, Locale(identifier: language.id))
        } else { content }
    }
}
private struct ChapterAppearanceStyle: ViewModifier {
    let preference: SharedAppearance
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        let dark=preference.mode=="dark" || (preference.mode=="system" && scheme == .dark)
        let tokens=AppearanceCatalog.tokens(preference,dark:dark)
        let paper=Color(chapterHex:tokens["paper"].string ?? (dark ? "#181612":"#F7F4EE"))
        content.tint(Color(chapterHex:AppearanceCatalog.value["palettes"][preference.palette].string ?? "#B0563A"))
            .foregroundStyle(Color(chapterHex:tokens["ink"].string ?? (dark ? "#EEE6D8":"#28231F")))
            .scrollContentBackground(.hidden).background(paper)
            .preferredColorScheme(preference.mode=="system" ? nil : (dark ? .dark:.light))
    }
}
private struct AppearanceSettings: View {
    @EnvironmentObject private var model: VaultModel
    @State private var error: String?
    private var preference: SharedAppearance { model.snapshot.appearance ?? .standard }
    private func binding(_ key: WritableKeyPath<SharedAppearance,String>) -> Binding<String> {
        Binding(get:{ preference[keyPath:key] },set:{value in
            var next=preference;next[keyPath:key]=value
            if key == \SharedAppearance.skin, let accent=AppearanceCatalog.value["skins"][value]["defaultAccent"].string { next.palette=accent }
            do { try model.saveAppearance(next); error=nil } catch { self.error="Appearance was not saved. " + error.localizedDescription }
        })
    }
    var body: some View {
        Section("Appearance — encrypted vault sync") {
            if !model.appearanceInitialized { Text("Complete a server sync before creating shared appearance settings on this device. Existing downloaded preferences remain editable offline.").font(.footnote) }
            Picker(model.t("prefs.mode"),selection:binding(\.mode)) { ForEach(SharedAppearance.modes,id:\.self) { Text(model.t("prefs.mode." + $0)).tag($0) } }.disabled(!model.appearanceInitialized).accessibilityIdentifier("appearance.mode")
            Picker("Style",selection:binding(\.skin)) { ForEach(SharedAppearance.skins,id:\.self) { Text(model.t("prefs.skin." + $0)).tag($0) } }.disabled(!model.appearanceInitialized).accessibilityIdentifier("appearance.skin")
            Picker(model.t("prefs.accent"),selection:binding(\.palette)) { ForEach(SharedAppearance.palettes,id:\.self) { Text(model.t("prefs.palette." + $0)).tag($0) } }.disabled(!model.appearanceInitialized).accessibilityIdentifier("appearance.palette")
            Text("Choices use the web app’s original colors and are saved inside encrypted vault settings. System mode follows each device. Offline edits queue for normal sync; AI stays disabled unless you explicitly enable it in the web app.").font(.footnote)
            if let error { Text(error).accessibilityIdentifier("appearance.error") }
        }
    }
}
// Original mobile book thumbnail (46×58), including spine and all five patterns.
// 'photo' is the original diagonal stripe skin, NOT a remote image request.
private struct NotebookCover: View {
    let color: String
    let pattern: String
    @Environment(\.layoutDirection) private var direction
    var body: some View {
        Canvas { context,size in
            let rect=CGRect(origin:.zero,size:size)
            context.fill(Path(roundedRect:rect,cornerRadius:4),with:.color(Color(chapterHex:color).opacity(0.13)))
            if pattern=="dots" {
                for x in stride(from:4.5,to:Double(size.width),by:9) { for y in stride(from:4.5,to:Double(size.height),by:9) {
                    context.fill(Path(ellipseIn:CGRect(x:x-1.4,y:y-1.4,width:2.8,height:2.8)),with:.color(Color(chapterHex:color).opacity(0.28)))
                }}
            } else if pattern=="lines" || pattern=="grid" {
                var lines=Path();let step=pattern=="lines" ? 8.0:9.0
                for y in stride(from:step,to:Double(size.height),by:step) { lines.move(to:CGPoint(x:0,y:y));lines.addLine(to:CGPoint(x:size.width,y:y)) }
                if pattern=="grid" { for x in stride(from:9.0,to:Double(size.width),by:9) { lines.move(to:CGPoint(x:x,y:0));lines.addLine(to:CGPoint(x:x,y:size.height)) } }
                context.stroke(lines,with:.color(Color(chapterHex:color).opacity(0.16)),lineWidth:1)
            } else if pattern=="photo" {
                var stripes=Path()
                for x in stride(from:-64.0,to:Double(size.width)+64,by:12) { stripes.move(to:CGPoint(x:x,y:0));stripes.addLine(to:CGPoint(x:x-Double(size.height),y:Double(size.height))) }
                context.stroke(stripes,with:.color(Color(chapterHex:color).opacity(0.18)),lineWidth:6)
            }
            context.fill(Path(CGRect(x:direction == .rightToLeft ? size.width-4:0,y:0,width:4,height:size.height)),with:.color(Color(chapterHex:color).opacity(0.85)))
        }.frame(width:46,height:58).clipShape(RoundedRectangle(cornerRadius:8)).overlay(RoundedRectangle(cornerRadius:8).stroke(Color(chapterHex:color).opacity(0.3),lineWidth:1)).accessibilityHidden(true)
    }
}

// UIKit navigation/tab hosts and Form/List backgrounds are opaque; tinting only
// the root does NOT render original web paper (verified in actual a5 screenshots).
func chapterToken(_ name:String,preference:SharedAppearance)->Color {
    Color(uiColor:UIColor { traits in
        let dark=preference.mode=="dark" || (preference.mode=="system" && traits.userInterfaceStyle == .dark)
        if let accent=AppearanceCatalog.accentToken(name,palette:preference.palette,dark:dark) {
            return UIColor(red:CGFloat(accent.r)/255,green:CGFloat(accent.g)/255,blue:CGFloat(accent.b)/255,alpha:CGFloat(accent.a))
        }
        let hex=AppearanceCatalog.tokens(preference,dark:dark)[name].string ?? (dark ? "#181612":"#F4EEE2")
        let value=UInt64(hex.trimmingCharacters(in:CharacterSet(charactersIn:"#")),radix:16) ?? 0
        return UIColor(red:CGFloat((value>>16)&255)/255,green:CGFloat((value>>8)&255)/255,blue:CGFloat(value&255)/255,alpha:1)
    })
}
struct ChapterScreenSurface: ViewModifier {
    @EnvironmentObject private var model:VaultModel
    func body(content:Content)->some View {
        let paper=chapterToken("paper",preference:model.snapshot.appearance ?? .standard)
        content.scrollContentBackground(.hidden).background(paper)
            .toolbarBackground(paper,for:.navigationBar,.tabBar)
            .toolbarBackground(.visible,for:.navigationBar,.tabBar)
    }
}

/// Mirrors the original web "[[" picker: other live downloaded entries,
/// title search, most recently updated first, at most eight results.
struct EntryLinkPicker: View {
    @EnvironmentObject private var model: VaultModel
    @Environment(\.dismiss) private var dismiss
    @State private var expected: VaultRecord
    @State private var query = ""
    @State private var error: String?
    let caret: RichCaret?
    let onDone: () -> Void
    init(entry: VaultRecord, caret: RichCaret? = nil, onDone: @escaping () -> Void = {}) { _expected = State(initialValue: entry); self.caret = caret; self.onDone = onDone }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    let candidates = model.snapshot.entryLinkCandidates(excluding: expected.id, query: query)
                    if candidates.isEmpty { Text(query.isEmpty ? "No other downloaded entries yet." : "No downloaded entries match.").foregroundStyle(.secondary).accessibilityIdentifier("link.empty") }
                    ForEach(candidates) { target in
                        Button {
                            do {
                                if let caret { try model.insertEntryLink(expected, to: target.id, at: caret) } else { try model.addEntryLink(expected, to: target.id) }
                                dismiss(); onDone()
                            } catch { self.error = error.localizedDescription }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(EntryLinkAuthoring.label(for: target)).font(.body)
                                Text(target.date.formatted(date: .abbreviated, time: .omitted)).font(.footnote).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }.accessibilityIdentifier("link.candidate." + target.id)
                    }
                } footer: {
                    Text((caret == nil ? "Adds a link at the end of this entry" : "Adds a link at your cursor") + ", the same link the web editor creates. Only downloaded entries are listed; it syncs when your server is reachable.").font(.footnote)
                }
                if let error { Text(error).foregroundStyle(.red).accessibilityIdentifier("link.error") }
            }.modifier(ChapterScreenSurface()).navigationTitle(model.t("editorx.slash.link")).navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search entry titles")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(model.t("common.cancel")) { dismiss() } } }
        }
    }
}
/// Original Editor template picker ("Insert"): the template's blocks at the cursor.
struct TemplateInsertPicker: View {
    @EnvironmentObject private var model: VaultModel
    @Environment(\.dismiss) private var dismiss
    let entry: VaultRecord
    let caret: RichCaret
    let onDone: () -> Void
    @State private var error: String?
    private var candidates: [VaultRecord] { model.templates.filter { $0.body["bodyJson"]?.string != nil } + model.builtinTemplates.map(\.seedRecord) }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    if candidates.isEmpty { Text("No templates with rich content. Create or edit templates in Start from template.").foregroundStyle(.secondary).accessibilityIdentifier("template.insert.empty") }
                    ForEach(candidates) { template in
                        Button {
                            do { try model.insertTemplate(entry, template: template, at: caret); dismiss(); onDone() } catch { self.error = "Template was not inserted. " + error.localizedDescription }
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(EntryTemplates.name(template)).font(.headline)
                                let preview = template.body["bodyText"]?.string ?? ""
                                if !preview.isEmpty { Text(preview).font(.footnote).foregroundStyle(.secondary).lineLimit(3) }
                            }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }.accessibilityIdentifier("template.insert." + template.id)
                    }
                } footer: { Text("Inserts the template's blocks at your cursor, like the web editor. Place the cursor in a top-level paragraph or heading.").font(.footnote) }
                if let error { Text(error).foregroundStyle(.red).accessibilityIdentifier("template.insert.error") }
            }.modifier(ChapterScreenSurface()).navigationTitle("Insert template").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(model.t("common.cancel")) { dismiss() } } }
        }
    }
}
/// Mirrors the original web TemplatesSheet "Use": synced templates only
/// (pristine built-in seeds are local to the device that seeded them).
struct TemplatePicker: View {
    private enum Target: Identifiable {
        case synced(VaultRecord), seed(BuiltinTemplate)
        var id: String { switch self { case .synced(let r): return r.id; case .seed(let s): return s.id } }
        var name: String { switch self { case .synced(let r): return EntryTemplates.name(r); case .seed(let s): return s.name } }
        var preview: String { switch self { case .synced(let r): return r.body["bodyText"]?.string ?? ""; case .seed(let s): return s.bodyText } }
        var storedName: String { switch self { case .synced(let r): return r.body["name"]?.string ?? ""; case .seed(let s): return s.name } }
    }
    @EnvironmentObject private var model: VaultModel
    @Environment(\.dismiss) private var dismiss
    @State private var journal: String
    @State private var error: String?
    @State private var creating = false
    @State private var renaming: Target?
    @State private var editingBody: BodyTarget?
    private struct BodyTarget: Identifiable { let id: String }
    @State private var armedDelete: Target?
    let onCreate: (String) -> Void
    init(journal: String, onCreate: @escaping (String) -> Void) { _journal = State(initialValue: journal); self.onCreate = onCreate }
    private func use(_ target: Target) {
        do {
            let entry: VaultRecord
            switch target { case .synced(let r): entry = try model.newEntryFromTemplate(r, journalID: journal); case .seed(let s): entry = try model.newEntryFromBuiltin(s, journalID: journal) }
            dismiss(); onCreate(entry.id)
        } catch { self.error = error.localizedDescription }
    }
    private func row(_ target: Target) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Button { use(target) } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(target.name).font(.headline)
                    if !target.preview.isEmpty { Text(target.preview).font(.footnote).foregroundStyle(.secondary).lineLimit(3) }
                }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }.buttonStyle(.borderless).accessibilityIdentifier("template.use." + target.id).accessibilityHint("Starts a new entry with this template")
            Menu {
                Button { renaming = target } label: { Label(model.t("common.rename"), systemImage: "pencil") }.accessibilityIdentifier("template.rename")
                // Web TemplateEditor body editing for synced templates and built-ins.
                switch target {
                case .synced(let record) where record.body["bodyJson"]?.string != nil:
                    Button { editingBody = BodyTarget(id: record.id) } label: { Label(model.t("templates.action.edit"), systemImage: "square.and.pencil") }.accessibilityIdentifier("template.edit")
                case .seed(let seed):
                    // Forks into a synced template only when the first change is applied.
                    Button { do { editingBody = BodyTarget(id: try model.prepareSeedEdit(seed).id) } catch { self.error = error.localizedDescription } } label: { Label(model.t("templates.action.edit"), systemImage: "square.and.pencil") }.accessibilityIdentifier("template.edit")
                default: EmptyView()
                }
                Button(role: .destructive) { armedDelete = target } label: { Label(model.t("common.delete"), systemImage: "trash") }.accessibilityIdentifier("template.delete")
            } label: {
                Image(systemName: "ellipsis.circle").imageScale(.large).frame(minWidth: 44, minHeight: 44)
            }.buttonStyle(.borderless).accessibilityLabel("Template actions for " + target.name).accessibilityIdentifier("template.actions." + target.id)
        }
    }
    var body: some View {
        NavigationStack {
            Form {
                Picker(model.t("shell.compose.notebook"), selection: $journal) { ForEach(model.journals) { Text($0.title).tag($0.journalID) } }.accessibilityIdentifier("template.notebook")
                Section {
                    if model.templates.isEmpty && model.builtinTemplates.isEmpty { Text("No templates. Create one to start entries with the same prompts.").foregroundStyle(.secondary).accessibilityIdentifier("template.empty") }
                    ForEach(model.templates) { row(.synced($0)) }
                    ForEach(model.builtinTemplates) { row(.seed($0)) }
                } header: { Text(model.t("templates.title")) } footer: {
                    Text("Starts a new entry with the template's exact content, like the web app. Built-in templates are the web app's own; renaming or deleting one syncs that change to your other devices. New templates made here have plain paragraphs; edit rich template content on the web.").font(.footnote)
                }
                if let error { Text(error).foregroundStyle(.red).accessibilityIdentifier("template.error") }
            }.modifier(ChapterScreenSurface()).navigationTitle("Start from template").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(model.t("common.cancel")) { dismiss() } }
                ToolbarItem(placement: .primaryAction) { Button { creating = true } label: { Label(model.t("templates.new"), systemImage: "plus") }.accessibilityIdentifier("template.new") }
            }
            .sheet(isPresented: $creating) { TemplateEditor(initialName: "", isNew: true) { name, text in try model.createTemplate(name: name, text: text) } }
            .sheet(item: $editingBody) { target in
                if let record = model.editableRecord(target.id), record.kind == "template" { RichEntryEditor(entry: record) }
            }
            .sheet(item: $renaming) { target in
                TemplateEditor(initialName: target.storedName, isNew: false) { name, _ in
                    switch target { case .synced(let r): try model.renameTemplate(r, name: name); case .seed(let s): try model.forkBuiltin(s, name: name) }
                }
            }
            .confirmationDialog("Delete this template?", isPresented: Binding(get: { armedDelete != nil }, set: { if !$0 { armedDelete = nil } }), titleVisibility: .visible, presenting: armedDelete) { target in
                Button(model.t("templates.action.delete"), role: .destructive) {
                    do {
                        switch target { case .synced(let r): try model.deleteTemplate(r); case .seed(let s): try model.forkBuiltin(s, deleted: true) }
                        error = nil
                    } catch { self.error = "Template changed or could not be deleted. " + error.localizedDescription }
                }.accessibilityIdentifier("template.confirmDelete")
            } message: { target in Text("“\(target.name)” is removed on every synced device. Entries already started from it are not changed.") }
        }
    }
}
/// Original web TemplateEditorView: name (blank saves as "Untitled template")
/// and, for a new template, a plain body. Renaming keeps the stored body bytes.
struct TemplateEditor: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: VaultModel
    let isNew: Bool
    let save: (String, String) throws -> Void
    @State private var name: String
    @State private var text = ""
    @State private var error: String?
    init(initialName: String, isNew: Bool, save: @escaping (String, String) throws -> Void) { self.isNew = isNew; self.save = save; _name = State(initialValue: initialName) }
    var body: some View {
        NavigationStack {
            Form {
                Section("Name") { TextField(model.t("templates.name.placeholder"), text: $name).accessibilityIdentifier("template.name") }
                if isNew {
                    Section { TextField("Prompts or starting text", text: $text, axis: .vertical).lineLimit(4...12).accessibilityIdentifier("template.body") } header: { Text("Body") } footer: { Text("Each line becomes a paragraph.") }
                }
                if let error { Text(error).foregroundStyle(.red).accessibilityIdentifier("template.editorError") }
            }.modifier(ChapterScreenSurface()).navigationTitle(isNew ? model.t("templates.new") : "Rename template").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(model.t("common.cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(model.t("common.save")) {
                        do { try save(name, text); dismiss() } catch { self.error = "Template was not saved. " + error.localizedDescription }
                    }.accessibilityIdentifier("template.save")
                }
            }
        }
    }
}
struct MoveEntryView: View {
    @EnvironmentObject private var model: VaultModel
    @Environment(\.dismiss) private var dismiss
    @State private var expected: VaultRecord
    @State private var notebookID: String
    @State private var error: String?
    init(entry: VaultRecord) { _expected = State(initialValue: entry); _notebookID = State(initialValue: entry.journalID) }
    var body: some View {
        NavigationStack {
            Form {
                Picker(model.t("shell.compose.notebook"), selection: $notebookID) {
                    Text("Choose a notebook").tag("")
                    ForEach(model.journals) { notebook in Text(notebook.title).tag(notebook.journalID) }
                }.accessibilityIdentifier("move.notebook")
                Text("Moves this entry without changing its original rich content, attachments, labels or creation date. Saved changes sync when your server is reachable.").font(.footnote)
                if let error { Text(error).foregroundStyle(.red).accessibilityIdentifier("move.error") }
            }.modifier(ChapterScreenSurface()).navigationTitle("Move entry")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(model.t("common.cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Move") { do { try model.moveEntry(expected, notebookID: notebookID); dismiss() } catch { self.error = error.localizedDescription } }
                        .disabled(!model.journals.contains { $0.journalID == notebookID })
                }
            }
        }
    }
}

private struct ChapterFontLicenses: View {
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:24) {
                ForEach(["hanken-grotesk","newsreader","spline-sans-mono"],id:\.self) { family in
                    if let url = Bundle.main.url(forResource:family+"-OFL",withExtension:"txt",subdirectory:"Fonts"), let license = try? String(contentsOf:url,encoding:.utf8) {
                        Text(license).font(.footnote).textSelection(.enabled).accessibilityIdentifier("license."+family)
                    } else { Text("Bundled font license unavailable: "+family).accessibilityIdentifier("license.missing."+family) }
                }
            }.padding()
        }.navigationTitle("Font licenses")
    }
}

// Dynamic Type relative styles are intentional; no fixed-size custom UIFont is
// installed globally. Onboarding stays on original native fonts while its strict
// audit diagnosis remains open. Unavailable/non-Latin glyphs use native fallback.
func chapterFont(_ role:ChapterFontRole,skin:String,size:CGFloat = 17,relativeTo style:Font.TextStyle = .body)->Font {
    .custom(ChapterTypeface.postscript(role,skin:skin),size:size,relativeTo:style)
}
#if DEBUG
private struct ChapterFontDiagnostic: View {
    var body: some View {
        NavigationStack { ScrollView {
            VStack(alignment:.leading,spacing:20) {
                ForEach(["HankenGrotesk-Regular","HankenGrotesk-Italic","Newsreader16pt-Regular","Newsreader16pt-Italic","SplineSansMono-Regular","SplineSansMono-Italic"],id:\.self) { name in
                    if let actual = UIFont(name:name,size:18) {
                        Text(actual.fontName).font(.custom(name,size:18,relativeTo:.body)).accessibilityIdentifier("font."+name)
                    } else { Text("Unavailable: "+name).accessibilityIdentifier("font.missing."+name) }
                }
                Text("Original fonts: PUBLIC synthetic typography only.").font(.footnote)
                NavigationLink("Original font licenses") { ChapterFontLicenses() }
            }.padding()
        } }
    }
}
/// Isolates the production CTA's layout from text inputs. This is an additional
/// required DEBUG diagnosis, never a replacement or suppression of real audits.
private struct NativeFullWidthActionAuditReproduction: View {
    @State private var tapped = false
    var body: some View {
        NavigationStack {
            Form { Text(tapped ? "Tapped" : "Public action layout comparison").font(.title2) }
                .navigationTitle("Action comparison")
                .safeAreaInset(edge:.bottom) {
                    Button { tapped=true } label: {
                        Text("Unlock and connect").font(.body).multilineTextAlignment(.center)
                            .fixedSize(horizontal:false,vertical:true).foregroundStyle(.white)
                            .frame(maxWidth:.infinity,minHeight:44)
                    }.buttonStyle(.borderedProminent).tint(.black)
                        .accessibilityIdentifier("repro.full-width-action").padding().background(.regularMaterial)
                }
        }
    }
}

/// A separate unchanged SecureField comparison; does not replace production tests
/// or the existing unmodified Form control, and never handles a real phrase.
private struct NativeSecureFieldAuditReproduction: View {
    @State private var text = ""
    var body: some View { NavigationStack { Form { SecureField("Public secure field",text:$text) }.navigationTitle("Secure field comparison") } }
}
#endif

struct NotebookDeletionView: View {
    @EnvironmentObject private var model: VaultModel
    @Environment(\.dismiss) private var dismiss
    @State private var plan: NotebookDeletionPlan
    @State private var confirmation = ""
    @State private var refreshing = false
    @State private var error: String?
    let onDeleted: () -> Void
    init(plan:NotebookDeletionPlan,onDeleted:@escaping ()->Void) { _plan = State(initialValue:plan); self.onDeleted = onDeleted }
    private func refresh() async {
        let previous = model.lastCompletePullID
        refreshing = true; defer { refreshing = false }
        await model.sync()
        guard let completed = model.lastCompletePullID, completed != previous else {
            error = "A full server pull did not complete. The deletion list is unchanged. " + (model.message ?? "Retry when your server is reachable."); return
        }
        do {
            guard let current = model.journals.first(where:{$0.id == plan.notebook.id}) else { throw ChapterError.conflict }
            plan = try model.prepareNotebookDeletion(current); confirmation = ""; error = nil
        } catch { self.error = "Notebook changed. Close and reopen deletion to review it. " + error.localizedDescription }
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Review downloaded data") {
                    Text(plan.notebook.title).font(.headline)
                    Text("This removes the notebook and " + String(plan.entries.count) + " entries currently downloaded on this device. An encrypted local original checkpoint, unsynced writing, rich drafts and media remain retained. This is recoverable deletion, NOT secure erasure.")
                    Text("Sync before confirming to include other devices’ entries. The original relay has no atomic notebook-wide transaction: unseen or concurrent remote entries may remain; later changes cause local confirmation/restore to refuse rather than overwrite them.").font(.footnote)
                    if model.canSync {
                        Button { Task { await refresh() } } label: {
                            if refreshing { ProgressView("Refreshing downloaded entries") } else { Text("Sync and refresh deletion list") }
                        }.disabled(refreshing || model.syncing)
                    }
                }
                Section("Downloaded entries in this deletion") {
                    if plan.entries.isEmpty { Text("No downloaded entries; only the notebook is removed.") }
                    ForEach(plan.entries) { entry in Text(entry.title) }
                }
                Section("Confirm recoverable deletion") {
                    TextField("Type delete",text:$confirmation).textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("notebook.delete.confirmation")
                    Button("Delete reviewed notebook and entries",role:.destructive) {
                        do { try model.deleteNotebook(plan); onDeleted(); dismiss() }
                        catch { self.error = "Nothing was intentionally discarded. The notebook changed, a sync/import is active, or encrypted storage could not save. Review/retry. " + error.localizedDescription }
                    }.disabled(confirmation != "delete" || refreshing || model.syncing).accessibilityIdentifier("notebook.delete.apply")
                }
                if let error { Text(error).accessibilityIdentifier("notebook.delete.error") }
            }.modifier(ChapterScreenSurface()).navigationTitle("Delete notebook")
            .toolbar { ToolbarItem(placement:.cancellationAction) { Button(model.t("common.cancel")) { dismiss() } } }
        }
    }
}

/// Web StyleFields colour row: the eight JCOLORS swatches. A notebook's existing other
/// colour stays selectable so opening and saving never rewrites it.
struct JournalColorSwatches: View {
    static let colors = ["#B0563A", "#4E8B85", "#6A6AA0", "#B08A2E", "#5A7BA6", "#6E8B5E", "#8E6A93", "#C06A4A"]
    @EnvironmentObject private var model: VaultModel
    @Binding var color: String
    var body: some View {
        let known = color.isEmpty || Self.colors.contains(where: { $0.caseInsensitiveCompare(color) == .orderedSame })
        let choices = known ? Self.colors : Self.colors + [color]
        let ink = chapterToken("ink", preference: model.snapshot.appearance ?? .standard)
        HStack(spacing: 0) {
            ForEach(Array(choices.enumerated()), id: \.offset) { index, hex in
                let selected = hex.caseInsensitiveCompare(color) == .orderedSame
                Button { color = hex } label: {
                    Circle().fill(Color(chapterHex: hex)).frame(width: 30, height: 30)
                        .overlay(Circle().inset(by: -3).stroke(selected ? ink : .clear, lineWidth: 2.5))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }.buttonStyle(.plain)
                .accessibilityLabel(model.t("journals.field.colour") + " \(index + 1)").accessibilityValue(hex)
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityIdentifier("notebook.color." + hex.replacingOccurrences(of: "#", with: "").lowercased())
            }
        }
    }
}

/// Web NewJournalSheet: name, colour, cover and "Start from" a template.
struct NewNotebookSheet: View {
    @EnvironmentObject private var model: VaultModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var color = JournalColorSwatches.colors[1]
    @State private var cover = "lines"
    @State private var template = "blank"
    @State private var error: String?
    let onEntry: (String) -> Void
    private let covers = ["lines", "dots", "grid", "plain", "photo"]
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        NotebookCover(color: color, pattern: cover).accessibilityHidden(true)
                        TextField(model.t("journals.name.placeholder"), text: $name).accessibilityIdentifier("notebook.new.name")
                    }
                }
                Section(model.t("journals.field.colour")) { JournalColorSwatches(color: $color) }
                Section {
                    Picker(model.t("journals.field.cover"), selection: $cover) { ForEach(covers, id: \.self) { Text(model.t("journals.cover." + $0)).tag($0) } }.accessibilityIdentifier("notebook.new.cover")
                    Picker(model.t("journals.field.startFrom"), selection: $template) {
                        Text(model.t("journals.blank")).tag("blank")
                        ForEach(model.templates) { Text(EntryTemplates.name($0).isEmpty ? model.t("journals.untitledTemplate") : EntryTemplates.name($0)).tag($0.id) }
                        ForEach(model.builtinTemplates) { Text($0.name).tag($0.id) }
                    }.accessibilityIdentifier("notebook.new.template")
                }
                if let error { Section { Text(error).accessibilityIdentifier("notebook.new.error") } }
            }.modifier(ChapterScreenSurface()).navigationTitle(model.t("journals.new")).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(model.t("common.cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button(model.t("journals.create")) { create() }.accessibilityIdentifier("notebook.new.create") }
            }
        }
    }
    private func create() {
        do {
            // Web: name || t('journals.untitled'), subtitle t('journals.new'); a template opens its first entry.
            let id = try model.createJournal(name: name.isEmpty ? model.t("journals.untitled") : name, subtitle: model.t("journals.new"), color: color, cover: cover)
            var entry: VaultRecord?
            if let synced = model.templates.first(where: { $0.id == template }) { entry = try model.newEntryFromTemplate(synced, journalID: id) }
            else if let seed = model.builtinTemplates.first(where: { $0.id == template }) { entry = try model.newEntryFromBuiltin(seed, journalID: id) }
            dismiss()
            if let entry { onEntry(entry.id) }
        } catch { self.error = error.localizedDescription }
    }
}


/// Web Search row extras: the matched-field tag (not shown for content) and the body snippet.
struct SearchHitDetail: View {
    @EnvironmentObject private var model: VaultModel
    let hit: ChapterSearch.Hit
    private var fieldName: String {
        switch hit.field { case .title: return model.t("shell.search.field.title"); case .label: return model.t("shell.search.field.label"); case .date: return model.t("shell.search.field.date"); case .content: return model.t("shell.search.field.content") }
    }
    var body: some View {
        let skin = model.snapshot.appearance?.skin ?? "paper"
        VStack(alignment: .leading, spacing: 4) {
            if hit.field != .content {
                Text(fieldName.uppercased())
                    .font(chapterFont(.mono, skin: skin, size: 10, relativeTo: .caption2)).tracking(0.5)
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(chapterToken("line", preference: model.snapshot.appearance ?? .standard)))
                    .accessibilityIdentifier("search.field." + hit.field.rawValue)
            }
            if let snippet = hit.snippet {
                Text(snippet).font(chapterFont(.ui, skin: skin, size: 12.5, relativeTo: .footnote)).foregroundStyle(.secondary).lineLimit(2)
                    .accessibilityIdentifier("search.snippet")
            }
        }.padding(.horizontal, 4).accessibilityElement(children: .combine)
    }
}


struct BadgeID: Identifiable, Equatable { let id: String }

@MainActor func badgeName(_ id: String, _ model: VaultModel) -> String {
    switch id {
    case "first-words": return model.t("badges.first-words.name"); case "streak-3": return model.t("badges.streak-3.name")
    case "streak-7": return model.t("badges.streak-7.name"); case "wordsmith": return model.t("badges.wordsmith.name")
    case "deep-dive": return model.t("badges.deep-dive.name"); case "first-interview": return model.t("badges.first-interview.name")
    case "on-camera": return model.t("badges.on-camera.name"); case "memory-keeper": return model.t("badges.memory-keeper.name")
    default: return id
    }
}
@MainActor func badgeDesc(_ id: String, _ model: VaultModel) -> String {
    switch id {
    case "first-words": return model.t("badges.first-words.desc"); case "streak-3": return model.t("badges.streak-3.desc")
    case "streak-7": return model.t("badges.streak-7.desc"); case "wordsmith": return model.t("badges.wordsmith.desc")
    case "deep-dive": return model.t("badges.deep-dive.desc"); case "first-interview": return model.t("badges.first-interview.desc")
    case "on-camera": return model.t("badges.on-camera.desc"); case "memory-keeper": return model.t("badges.memory-keeper.desc")
    default: return ""
    }
}

/// Web BadgeMedallion: accent-soft disc with an accent ring when earned; dimmed and grey when locked.
struct BadgeMedallion: View {
    @EnvironmentObject private var model: VaultModel
    let earned: Bool
    var size: CGFloat = 44
    var body: some View {
        let p = model.snapshot.appearance ?? .standard
        ZStack {
            Circle().fill(chapterToken(earned ? "accent-soft" : "surface-2", preference: p))
            Circle().strokeBorder(chapterToken(earned ? "accent-line" : "line", preference: p), lineWidth: earned ? 3 : 1)
            Image(systemName: "rosette").font(.system(size: size * 0.48)).foregroundStyle(chapterToken(earned ? "accent-ink" : "ink-3", preference: p))
        }.frame(width: size, height: size).opacity(earned ? 1 : 0.38).saturation(earned ? 1 : 0).accessibilityHidden(true)
    }
}

/// Web Preferences badge gallery: the eight badges in fixed order, two per row.
struct BadgeGallerySection: View {
    @EnvironmentObject private var model: VaultModel
    var body: some View {
        let earned = model.earnedBadges
        let p = model.snapshot.appearance ?? .standard
        Section(model.t("badges.gallery.title")) {
            Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                ForEach(Array(stride(from: 0, to: ChapterBadges.order.count, by: 2)), id: \.self) { i in
                    GridRow {
                        ForEach(ChapterBadges.order[i..<min(i + 2, ChapterBadges.order.count)], id: \.self) { id in
                            let has = earned.contains(id)
                            VStack(spacing: 8) {
                                BadgeMedallion(earned: has)
                                Text(badgeName(id, model)).font(chapterFont(.ui, skin: p.skin, size: 11.5, relativeTo: .caption)).fontWeight(has ? .bold : .medium)
                                    .foregroundStyle(has ? chapterToken("accent-ink", preference: p) : Color.secondary).multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 12).padding(.horizontal, 8)
                            .background(chapterToken(has ? "accent-soft" : "paper", preference: p), in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(chapterToken(has ? "accent-line" : "line", preference: p)))
                            .accessibilityElement(children: .combine)
                            .accessibilityHint(badgeDesc(id, model))
                            .accessibilityValue(has ? "Earned" : "Not earned yet")
                            .accessibilityIdentifier("badge." + id)
                        }
                    }
                }
            }.padding(.vertical, 4)
        }
    }
}

/// Web BadgeCelebration: one newly earned badge at a time; dismissing marks it seen.
struct BadgeCelebrationView: View {
    @EnvironmentObject private var model: VaultModel
    let id: String
    var body: some View {
        let p = model.snapshot.appearance ?? .standard
        VStack(spacing: 16) {
            BadgeMedallion(earned: true, size: 96)
            Text(model.t("badges.celebrate.title").uppercased()).font(chapterFont(.mono, skin: p.skin, size: 12, relativeTo: .caption)).tracking(1).foregroundStyle(.secondary)
            Text(badgeName(id, model)).font(chapterFont(.heading, skin: p.skin, size: 28, relativeTo: .title)).multilineTextAlignment(.center).accessibilityIdentifier("badge.celebrate.name")
            Text(badgeDesc(id, model)).font(chapterFont(.ui, skin: p.skin, size: 15, relativeTo: .body)).multilineTextAlignment(.center).foregroundStyle(.secondary)
            Button(model.t("badges.celebrate.dismiss")) { model.dismissBadgeCelebration() }
                .buttonStyle(.borderedProminent).controlSize(.large).accessibilityIdentifier("badge.celebrate.dismiss")
        }
        .padding(32).frame(maxWidth: .infinity, maxHeight: .infinity).modifier(ChapterScreenSurface())
        .presentationDetents([.medium]).interactiveDismissDisabled()
    }
}


/// Web InterviewTypesSheet: every guided-interview type (built-in seeds and the user's
/// own) with edit and two-tap delete. Built-ins fork into synced records on first change.
struct InterviewTypesView: View {
    @EnvironmentObject private var model: VaultModel
    @Environment(\.dismiss) private var dismiss
    enum Target: Identifiable, Hashable {
        case synced(String), seed(String), new
        var id: String { switch self { case .synced(let r): return "r:" + r; case .seed(let s): return "s:" + s; case .new: return "new" } }
    }
    @State private var editing: Target?
    @State private var armedDelete: String?
    @State private var error: String?
    private func row(id: String, name: String, intro: String, builtin: Bool, edit: Target, delete: @escaping () throws -> Void) -> some View {
        let p = model.snapshot.appearance ?? .standard
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 7) {
                    Text(name.isEmpty ? model.t("common.untitled") : name).font(chapterFont(.prose, skin: p.skin, size: 15.5, relativeTo: .body)).fontWeight(.medium).lineLimit(1)
                    if builtin {
                        Text(model.t("assistant.types.builtin")).font(chapterFont(.mono, skin: p.skin, size: 10, relativeTo: .caption2))
                            .padding(.horizontal, 6).padding(.vertical, 1).overlay(RoundedRectangle(cornerRadius: 6).stroke(chapterToken("line", preference: p)))
                    }
                }
                if !intro.isEmpty { Text(intro).font(chapterFont(.ui, skin: p.skin, size: 12, relativeTo: .caption)).foregroundStyle(.secondary).lineLimit(1) }
            }.frame(maxWidth: .infinity, alignment: .leading).accessibilityElement(children: .combine)
            if armedDelete == id {
                Button(model.t("assistant.types.deleteConfirm"), role: .destructive) { do { try delete(); armedDelete = nil } catch { self.error = error.localizedDescription } }
                    .buttonStyle(.borderedProminent).frame(minHeight: 44).accessibilityIdentifier("interview.confirmDelete")
            } else {
                Button { armedDelete = nil; editing = edit } label: { Image(systemName: "pencil").frame(minWidth: 44, minHeight: 44) }
                    .buttonStyle(.borderless).accessibilityLabel(model.t("common.edit")).accessibilityIdentifier("interview.edit." + id)
                Button { armedDelete = id } label: { Image(systemName: "xmark").frame(minWidth: 44, minHeight: 44) }
                    .buttonStyle(.borderless).accessibilityLabel(model.t("common.delete")).accessibilityIdentifier("interview.delete." + id)
            }
        }
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 9) {
                    let seeds = model.builtinInterviews, synced = model.interviewTypes
                    if seeds.isEmpty && synced.isEmpty { Text(model.t("assistant.types.empty")).foregroundStyle(.secondary).padding(.vertical, 22).accessibilityIdentifier("interview.empty") }
                    ForEach(seeds) { seed in
                        card(row(id: seed.slug, name: model.t(seed.nameKey), intro: model.t(seed.introKey), builtin: true, edit: .seed(seed.slug)) { try model.forkBuiltinInterview(seed, deleted: true) })
                    }
                    ForEach(synced) { r in
                        card(row(id: r.id, name: r.body["name"]?.string ?? "", intro: r.body["intro"]?.string ?? "", builtin: r.body["builtin"]?.string != nil, edit: .synced(r.id)) { try model.deleteInterviewType(r) })
                    }
                    Button { armedDelete = nil; editing = .new } label: { Label(model.t("assistant.types.new"), systemImage: "plus").frame(maxWidth: .infinity, minHeight: 44) }
                        .buttonStyle(.bordered).accessibilityIdentifier("interview.new")
                    if let error { Text(error).font(.footnote).accessibilityIdentifier("interview.error") }
                }.padding(16)
            }
            .modifier(ChapterScreenSurface()).navigationTitle(model.t("assistant.types.title")).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(model.t("common.done")) { dismiss() } } }
            .sheet(item: $editing) { InterviewTypeEditor(target: $0) }
        }
    }
    private func card<V: View>(_ content: V) -> some View {
        let p = model.snapshot.appearance ?? .standard
        return content.padding(.horizontal, 14).padding(.vertical, 6)
            .background(chapterToken("paper", preference: p), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(chapterToken("line", preference: p)))
    }
}

/// Web interview-type EditorView: name, intro and prompt; save trims, empty name → untitled.
struct InterviewTypeEditor: View {
    @EnvironmentObject private var model: VaultModel
    @Environment(\.dismiss) private var dismiss
    let target: InterviewTypesView.Target
    @State private var name = ""
    @State private var intro = ""
    @State private var prompt = ""
    @State private var loaded = false
    @State private var error: String?
    private var record: VaultRecord? { if case .synced(let id) = target { return model.interviewTypes.first { $0.id == id } }; return nil }
    private var seed: InterviewTypes.Builtin? { if case .seed(let slug) = target { return model.builtinInterviews.first { $0.slug == slug } }; return nil }
    var body: some View {
        NavigationStack {
            Form {
                Section(model.t("assistant.types.name")) { TextField(model.t("assistant.types.namePlaceholder"), text: $name).accessibilityIdentifier("interview.name") }
                Section(model.t("assistant.types.intro")) { TextField(model.t("assistant.types.introPlaceholder"), text: $intro).accessibilityIdentifier("interview.intro") }
                Section(model.t("assistant.types.prompt")) { TextField(model.t("assistant.types.promptPlaceholder"), text: $prompt, axis: .vertical).lineLimit(6...14).accessibilityIdentifier("interview.prompt") }
                if let error { Section { Text(error).accessibilityIdentifier("interview.editor.error") } }
            }
            .modifier(ChapterScreenSurface()).navigationTitle(target == .new ? model.t("assistant.types.new") : model.t("assistant.types.edit")).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(model.t("common.cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button(target == .new ? model.t("assistant.types.create") : model.t("assistant.types.save")) { save() }.accessibilityIdentifier("interview.save") }
            }
            .onAppear {
                guard !loaded else { return }; loaded = true
                if let record { name = record.body["name"]?.string ?? ""; intro = record.body["intro"]?.string ?? ""; prompt = record.body["prompt"]?.string ?? "" }
                else if let seed { name = model.t(seed.nameKey); intro = model.t(seed.introKey); prompt = seed.prompt }
            }
        }
    }
    private func save() {
        do {
            switch target {
            case .new: try model.createInterviewType(name: name, intro: intro, prompt: prompt)
            case .synced: guard let record else { throw ChapterError.conflict }; try model.editInterviewType(record, name: name, intro: intro, prompt: prompt)
            case .seed: guard let seed else { throw ChapterError.conflict }; try model.forkBuiltinInterview(seed, name: name, intro: intro, prompt: prompt)
            }
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}


/// Web ExportJournalSheet: pick a notebook, build the plaintext archive on this device,
/// then hand it to the share sheet (Save to Files, AirDrop…). The web's wording about
/// "downloads" doesn't fit iOS, so those three lines are native. The archive file is
/// deleted when this sheet closes, when the vault locks, and on the next launch.
/// Web ImportDayOneSheet: pick the Day One JSON export .zip, read it on this device, show what
/// it holds, then write encrypted entries and media through the normal vault paths.
struct ImportDayOneView: View {
    @EnvironmentObject private var model: VaultModel
    @Environment(\.dismiss) private var dismiss
    private enum Step { case pick, reading, ready(DayOneArchive), working, done(ChapterDayOneImport.Summary), error(String) }
    @State private var step: Step = .pick
    @State private var picking = false
    @State private var task: Task<Void, Never>?
    private var busy: Bool {
        switch step { case .reading, .working: return true; default: return false }
    }
    var body: some View {
        let p = model.snapshot.appearance ?? .standard
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) { content(p) }.padding(16)
            }
            .modifier(ChapterScreenSurface()).navigationTitle(model.t("vault.import.title")).navigationBarTitleDisplayMode(.inline)
            .toolbar { if !busy { ToolbarItem(placement: .cancellationAction) { Button(model.t("common.close")) { dismiss() }.accessibilityIdentifier("import.close") } } }
        }
        .interactiveDismissDisabled(busy)
        .fileImporter(isPresented: $picking, allowedContentTypes: [.zip]) { result in
            switch result {
            case .success(let url): read(url)
            case .failure(let error): step = .error(error.localizedDescription)
            }
        }
        .onDisappear { task?.cancel() }
    }
    @ViewBuilder private func content(_ p: SharedAppearance) -> some View {
        switch step {
        case .pick:
            Text(model.t("vault.import.pickBody")).font(.subheadline)
            Button { picking = true } label: {
                VStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.down").font(.title2).foregroundStyle(chapterToken("accent", preference: p)).accessibilityHidden(true)
                    Text(model.t("vault.import.dropTitle")).font(.subheadline.weight(.semibold)).foregroundStyle(chapterToken("ink", preference: p)).multilineTextAlignment(.center)
                    Text(model.t("vault.import.dropHint")).font(.footnote).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 44).padding(.vertical, 24).padding(.horizontal, 16)
                .background(chapterToken("paper", preference: p), in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(chapterToken("line", preference: p), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
            }.buttonStyle(.plain).accessibilityElement(children: .combine).accessibilityAddTraits(.isButton).accessibilityIdentifier("import.choose")
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--chapter-dayone-fixture") {
                Button("Use the public Day One test export") { useFixture() }.frame(minHeight: 44).accessibilityIdentifier("import.fixture")
            }
            #endif
        case .reading:
            ProgressView().frame(maxWidth: .infinity, minHeight: 44).accessibilityIdentifier("import.reading")
        case .ready(let archive):
            Text(model.t("vault.import.readyLead")).font(.subheadline)
            summaryRow(model.t("vault.import.row.notebooks"), archive.journals.count, id: "row.notebooks", p)
            summaryRow(model.t("vault.import.row.entries"), archive.entryCount, id: "row.entries", p)
            summaryRow(model.t("vault.import.row.media"), archive.mediaCount, id: "row.media", p)
            Text(model.t("vault.import.readyBody")).font(.footnote)
            HStack {
                Button(model.t("common.back")) { step = .pick }.buttonStyle(.bordered).frame(minHeight: 44).accessibilityIdentifier("import.back")
                Spacer()
                Button(model.tp("vault.import.cta", count: archive.entryCount)) { run(archive) }.buttonStyle(.borderedProminent).frame(minHeight: 44).accessibilityIdentifier("import.run")
            }
        case .working:
            let progress = model.dayOneProgress
            let current = progress?.current ?? ""
            VStack(spacing: 10) {
                ProgressView(value: Double(progress?.done ?? 0), total: Double(max(progress?.total ?? 0, 1)))
                Text(model.t("vault.import.working")).font(.subheadline.weight(.semibold))
                Text(current.isEmpty ? model.t("vault.import.encrypting") : model.t("vault.import.writing", ["title": current])).font(.footnote).multilineTextAlignment(.center)
                Text(model.tp("vault.import.progress", count: progress?.total ?? 0, ["n": String(progress?.done ?? 0)])).font(.caption.monospaced()).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity).accessibilityElement(children: .combine).accessibilityIdentifier("import.working")
        case .done(let summary):
            VStack(spacing: 6) {
                Image(systemName: "checkmark.circle").font(.title).foregroundStyle(chapterToken("accent", preference: p)).accessibilityHidden(true)
                Text(model.t("vault.import.done")).font(.subheadline.weight(.semibold)).accessibilityIdentifier("import.done")
            }.frame(maxWidth: .infinity)
            summaryRow(model.t("vault.import.sum.entries"), summary.entries, id: "sum.entries", p)
            summaryRow(model.t("vault.import.sum.journals"), summary.journals, id: "sum.journals", p)
            summaryRow(model.t("vault.import.sum.media"), summary.media, id: "sum.media", p)
            if summary.skippedMedia > 0 { summaryRow(model.t("vault.import.sum.skipped"), summary.skippedMedia, id: "sum.skipped", p) }
            Text(model.t("vault.import.doneBody")).font(.footnote)
            HStack {
                Spacer()
                Button(model.t("common.done")) { dismiss() }.buttonStyle(.borderedProminent).frame(minHeight: 44).accessibilityIdentifier("import.finish")
            }
        case .error(let message):
            Text(model.t("vault.import.error")).font(.subheadline)
            Text(message).font(.caption.monospaced()).padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .background(chapterToken("paper", preference: p), in: RoundedRectangle(cornerRadius: 10)).accessibilityIdentifier("import.errorMessage")
            HStack {
                Button(model.t("common.close")) { dismiss() }.buttonStyle(.bordered).frame(minHeight: 44)
                Spacer()
                Button(model.t("vault.import.pickAnother")) { step = .pick }.buttonStyle(.borderedProminent).frame(minHeight: 44).accessibilityIdentifier("import.pickAnother")
            }
        }
    }
    private func summaryRow(_ label: String, _ value: Int, id: String, _ p: SharedAppearance) -> some View {
        HStack { Text(label); Spacer(); Text(String(value)).font(.body.monospaced().weight(.semibold)) }
            .font(.footnote).padding(.horizontal, 12).padding(.vertical, 8)
            .background(chapterToken("paper", preference: p), in: RoundedRectangle(cornerRadius: 10))
            .accessibilityElement(children: .combine).accessibilityIdentifier("import." + id)
    }
    private func read(_ url: URL) {
        step = .reading
        task = Task {
            do { step = .ready(try await model.readDayOneArchive(url)) }
            catch is CancellationError { step = .pick }
            catch { step = .error(error.localizedDescription) }
        }
    }
    private func run(_ archive: DayOneArchive) {
        step = .working
        task = Task {
            do { step = .done(try await model.importDayOne(archive)) }
            catch { step = .error(error.localizedDescription) }
        }
    }
    #if DEBUG
    private func useFixture() {
        do { read(try model.publicDayOneFixture()) } catch { step = .error(error.localizedDescription) }
    }
    #endif
}

struct ExportJournalView: View {
    @EnvironmentObject private var model: VaultModel
    @Environment(\.dismiss) private var dismiss
    private enum Step: Equatable { case pick, working, done(URL, ChapterExport.Summary), error(String) }
    @State private var step: Step = .pick
    @State private var task: Task<Void, Never>?
    var body: some View {
        let p = model.snapshot.appearance ?? .standard
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) { content(p) }.padding(16)
            }
            .modifier(ChapterScreenSurface()).navigationTitle(model.t("vault.export.title")).navigationBarTitleDisplayMode(.inline)
            .toolbar { if step != .working { ToolbarItem(placement: .cancellationAction) { Button(model.t("common.close")) { dismiss() }.accessibilityIdentifier("export.close") } } }
        }
        .interactiveDismissDisabled(step == .working)
        .onDisappear { task?.cancel(); model.discardExports() }
    }
    @ViewBuilder private func content(_ p: SharedAppearance) -> some View {
        switch step {
        case .pick:
            let counts = Dictionary(model.entries.map { ($0.journalID, 1) }, uniquingKeysWith: +)
            let options = model.journals.filter { (counts[$0.journalID] ?? 0) > 0 }
            Text(model.t("vault.export.pickBody")).font(.subheadline)
            if options.isEmpty { Text(model.t("vault.export.empty")).font(.footnote).foregroundStyle(.secondary).accessibilityIdentifier("export.empty") }
            ForEach(options) { journal in
                Button { run(journal) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "book.closed").foregroundStyle(chapterToken("accent", preference: p)).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(journal.body["name"]?.string ?? journal.title).font(.subheadline.weight(.semibold)).foregroundStyle(chapterToken("ink", preference: p))
                            Text(model.tp("vault.export.entries", count: counts[journal.journalID] ?? 0)).font(.footnote).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.forward").foregroundStyle(.secondary).accessibilityHidden(true)
                    }.padding(12).frame(minHeight: 44)
                    .background(chapterToken("paper", preference: p), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(chapterToken("line", preference: p)))
                }.buttonStyle(.plain).accessibilityElement(children: .combine).accessibilityAddTraits(.isButton).accessibilityIdentifier("export.pick." + journal.journalID)
            }
            Text(model.t("vault.export.readyBody")).font(.footnote)
            Text("The archive is not encrypted. Once you save or share it, it’s as readable as the journal itself — keep it somewhere you trust.").font(.footnote).foregroundStyle(.secondary)
        case .working:
            let progress = model.exportProgress
            VStack(spacing: 10) {
                ProgressView(value: Double(progress?.done ?? 0), total: Double(max(progress?.total ?? 0, 1)))
                Text(model.t("vault.export.working")).font(.subheadline.weight(.semibold))
                if let current = progress?.current, !current.isEmpty { Text(model.t("vault.export.writing", ["name": current])).font(.footnote).multilineTextAlignment(.center) }
                Text(model.t("vault.export.progress", ["n": String(progress?.done ?? 0), "count": String(progress?.total ?? 0)])).font(.caption.monospaced()).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity).accessibilityElement(children: .combine).accessibilityIdentifier("export.working")
        case .done(let url, let summary):
            VStack(spacing: 6) {
                Image(systemName: "checkmark.circle").font(.title).foregroundStyle(chapterToken("accent", preference: p)).accessibilityHidden(true)
                Text(model.t("vault.export.done")).font(.subheadline.weight(.semibold)).accessibilityIdentifier("export.done")
                Text(summary.filename).font(.caption.monospaced()).foregroundStyle(.secondary).multilineTextAlignment(.center).accessibilityIdentifier("export.filename")
            }.frame(maxWidth: .infinity)
            summaryRow(model.t("vault.export.sum.entries"), summary.entries, id: "entries", p)
            summaryRow(model.t("vault.export.sum.media"), summary.media, id: "media", p)
            if summary.missingMedia > 0 { summaryRow(model.t("vault.export.sum.missing"), summary.missingMedia, id: "missing", p) }
            Text("Share it to Files, AirDrop or another app to keep it. The archive explains its own format, and the full specification is linked from its README.").font(.footnote)
            if summary.missingMedia > 0 { Text(model.t("vault.export.missingBody")).font(.footnote) }
            ShareLink(item: url) { Label("Save or share the archive", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity, minHeight: 44) }
                .buttonStyle(.borderedProminent).accessibilityIdentifier("export.share")
            HStack {
                Button(model.t("vault.export.again")) { model.discardExports(); step = .pick }.buttonStyle(.bordered).frame(minHeight: 44).accessibilityIdentifier("export.again")
                Spacer()
                Button(model.t("common.done")) { dismiss() }.buttonStyle(.bordered).frame(minHeight: 44)
            }
        case .error(let message):
            Text(model.t("vault.export.error")).font(.subheadline)
            Text(message).font(.caption.monospaced()).padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .background(chapterToken("paper", preference: p), in: RoundedRectangle(cornerRadius: 10)).accessibilityIdentifier("export.errorMessage")
            HStack {
                Button(model.t("common.close")) { dismiss() }.buttonStyle(.bordered).frame(minHeight: 44)
                Spacer()
                Button(model.t("common.back")) { step = .pick }.buttonStyle(.borderedProminent).frame(minHeight: 44).accessibilityIdentifier("export.back")
            }
        }
    }
    private func summaryRow(_ label: String, _ value: Int, id: String, _ p: SharedAppearance) -> some View {
        HStack { Text(label); Spacer(); Text(String(value)).font(.body.monospaced().weight(.semibold)) }
            .font(.footnote).padding(.horizontal, 12).padding(.vertical, 8)
            .background(chapterToken("paper", preference: p), in: RoundedRectangle(cornerRadius: 10))
            .accessibilityElement(children: .combine).accessibilityIdentifier("export.sum." + id)
    }
    private func run(_ journal: VaultRecord) {
        step = .working
        task = Task {
            do { let (url, summary) = try await model.exportJournal(journal); step = .done(url, summary) }
            catch is CancellationError { step = .pick }
            catch { step = .error(error.localizedDescription) }
        }
    }
}
