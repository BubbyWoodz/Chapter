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
            Form {
                Section { Text("Your journal. Your server.").font(.title2).accessibilityAddTraits(.isHeader).accessibilityIdentifier("connection.heading")
                    Text("Connect directly over your local network or Tailscale. No Chapter account is required.")
                    Text("Native preview: feature coverage is incomplete. Use the web app for advanced features and recovery-phrase creation/rotation.").font(.footnote).fixedSize(horizontal:false,vertical:true) }
                Section {
                    Text("Server").font(.headline).fixedSize(horizontal:false,vertical:true).accessibilityAddTraits(.isHeader)
                    TextField("Server URL", text: $server).font(.body).fixedSize(horizontal: false, vertical: true).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityLabel("Server URL").accessibilityIdentifier("connection.server").focused($focusedField,equals:.server).submitLabel(.next).onSubmit {focusedField = .phrase}
                    Text("HTTPS with a trusted certificate is required, including on Tailscale. Include your server’s path prefix.").font(.footnote).fixedSize(horizontal: false, vertical: true)
                }
                Section {
                    Text("Unlock vault").font(.headline).fixedSize(horizontal:false,vertical:true).accessibilityAddTraits(.isHeader)
                    SecureField("12 words", text: $phrase).font(.body).fixedSize(horizontal: false, vertical: true).accessibilityLabel("12-word recovery phrase").accessibilityIdentifier("connection.phrase").focused($focusedField,equals:.phrase).submitLabel(.done).onSubmit {focusedField=nil}.textInputAutocapitalization(.never).autocorrectionDisabled().privacySensitive()
                    Text("The phrase stays on this device and is not saved. A device passcode is required to protect offline journals. Face ID or device authentication protects the local storage key.").font(.footnote).fixedSize(horizontal: false, vertical: true)

                }
                if let message = model.message { Section { Text(message).accessibilityLabel("Connection status: \(message)").accessibilityIdentifier("connection.status") } }

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

struct ChapterTabs: View {
    @EnvironmentObject private var model: VaultModel
    var body: some View {
        TabView {
            EntryList().tabItem { Label("Journal", systemImage: "book") }
            CalendarView().tabItem { Label("Calendar", systemImage: "calendar") }
            NotebookList().tabItem { Label("Notebooks", systemImage: "books.vertical") }
            SettingsView().tabItem { Label("Settings", systemImage: "gearshape") }
        }.font(chapterFont(.ui,skin:model.snapshot.appearance?.skin ?? "paper"))
    }
}
struct EntryList: View {
    @EnvironmentObject private var model: VaultModel
    @State private var query = ""
    @State private var compose = false
    let journal: String?
    init(journal: String? = nil) { self.journal = journal }
    var filtered: [VaultRecord] { model.entries.filter(matches) }
    private func matches(_ entry: VaultRecord) -> Bool {
        if let journal, entry.journalID != journal { return false }
        guard !query.isEmpty else { return true }
        let labelText = entry.labels.joined(separator: " ")
        let searchable = [entry.title, entry.text, labelText].joined(separator: " ")
        return searchable.localizedCaseInsensitiveContains(query)
    }
    var body: some View {
        NavigationStack {
            List {
                if filtered.isEmpty { Text(query.isEmpty ? "No downloaded entries. Sync or create your first entry." : "No matching entries.") }
                ForEach(filtered) { entry in NavigationLink { EntryDetail(entryID: entry.id) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.title).font(chapterFont(.heading,skin:model.snapshot.appearance?.skin ?? "paper",size:20,relativeTo:.headline))
                        Text(entry.text).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                        Text(entry.date, format: .dateTime.month().day().year()).font(.caption).foregroundStyle(.secondary)
                    }
                }}
            }
            .modifier(ChapterScreenSurface()).navigationTitle("Journal").searchable(text: $query, prompt: "Search this device")
            .refreshable { await model.sync() }
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { compose = true } label: { Label("New entry", systemImage: "square.and.pencil") } } }
            .sheet(isPresented: $compose) { EntryEditor(journal: journal ?? model.journals.first?.journalID ?? "default") }
        }
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
    @State private var showingActions = false
    @State private var showingPlainEdit = false
    @State private var previewURL: URL?
    @State private var loadingMedia: String?
    @State private var mediaError: String?
    @Environment(\.dismiss) private var dismiss
    var entry: VaultRecord? { model.entries.first { $0.id == entryID } }
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
                                Button("Move to notebook") { showingActions = false; moving = true }.frame(minHeight:44).disabled(model.journals.isEmpty)
                                Button("Delete entry",role:.destructive) { showingActions = false; deletionExpected = entry; deleting = true }.frame(minHeight:44)
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
                        } else { Text(entry.text).font(chapterFont(.prose,skin:model.snapshot.appearance?.skin ?? "paper",size:18)).textSelection(.enabled) }
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
                        if let mediaError { Text(mediaError).font(.footnote).foregroundStyle(.red) }
                        if !entry.editablePlainText { Text("Rich structure is preserved. Native editing supports formatted runs and adding text blocks. Selection-based editing, existing block restructuring and custom-node editing remain incomplete.").font(.footnote).foregroundStyle(.secondary) }
                    }.padding().frame(maxWidth: .infinity, alignment: .leading)
                }
                .toolbar {
                    if entry.editablePlainText {
                        Button("Edit") { showingPlainEdit.toggle() }.accessibilityValue(showingPlainEdit ? "Expanded":"Collapsed")
                    } else if entry.body["bodyJson"]?.string.flatMap({ try? RichDocument(json: $0) }) != nil { Button("Edit") { editRich = true; editing = true } }

                }
                .sheet(isPresented: $editing) {
                    if entry.editablePlainText && !editRich { EntryEditor(existing: entry, journal: entry.journalID) }
                    else if let raw = entry.body["bodyJson"]?.string, (try? RichDocument(json: raw)) != nil { RichEntryEditor(entry: entry) }
                }
                .sheet(isPresented: $moving) { MoveEntryView(entry: entry) }
                .sheet(isPresented: $editingMetadata) { EntryMetadataEditor(entry: entry) }
                .confirmationDialog("Delete this entry on all synced devices?", isPresented: $deleting, titleVisibility: .visible) {
                    Button("Delete entry", role: .destructive) { do { guard let deletionExpected else { throw ChapterError.conflict }; try model.deleteEntry(deletionExpected); dismiss() } catch { model.message = error.localizedDescription } }
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
                Picker("Notebook", selection: $draft.journal) {
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
            }.modifier(ChapterScreenSurface()).navigationTitle(draft.expected == nil ? "New entry" : "Edit entry")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() }.disabled(error != nil && !recoverySaved).accessibilityIdentifier("writing.close") }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { save(); if error == nil { dismiss() } } }
            }
            .onChange(of: draft.title) { _, _ in save() }.onChange(of: draft.text) { _, _ in save() }
            .onChange(of: draft.labels) { _, _ in save() }.onChange(of: draft.date) { _, _ in save() }
            .onChange(of: draft.journal) { _, _ in save() }
            .interactiveDismissDisabled(error != nil && !recoverySaved)
            .confirmationDialog("Save this writing as a new entry?", isPresented: $copying, titleVisibility: .visible) {
                Button("Save new text entry") { save(asNew: true) }
                Button("Cancel", role: .cancel) {}
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
                DatePicker("Entry date and time",selection:$date).accessibilityIdentifier("metadata.date")
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
                ToolbarItem(placement:.cancellationAction) { Button("Cancel") { if hasChanges { discarding = true } else { dismiss() } } }
                ToolbarItem(placement:.confirmationAction) { Button("Save") { save() } }
            }.interactiveDismissDisabled(hasChanges)
            .confirmationDialog("Discard unsaved metadata changes?",isPresented:$discarding,titleVisibility:.visible) {
                Button("Discard changes",role:.destructive) { dismiss() }; Button("Keep editing",role:.cancel) {}
            }
        }
    }
}
struct NotebookList: View {
    @EnvironmentObject private var model: VaultModel
    @State private var name = ""
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
                                Text("\(model.entries.filter { $0.journalID == journal.journalID }.count) entries").font(.caption).foregroundStyle(.secondary)
                            }
                        }.padding(.vertical,6)
                    }
                    Button { editing = journal } label: { Image(systemName: "pencil").frame(minWidth: 44, minHeight: 44) }
                        .buttonStyle(.borderless).accessibilityLabel("Edit notebook " + journal.title)
                }.listRowBackground(chapterToken("surface",preference:model.snapshot.appearance ?? .standard))
            } }
                .sheet(item: $editing) { NotebookEditor(journal: $0) }
                .modifier(ChapterScreenSurface()).navigationTitle("Notebooks").toolbar { Button { adding = true } label: { Label("New notebook", systemImage: "plus") } }
                .alert("New notebook", isPresented: $adding) {
                    TextField("Name", text: $name)
                    Button("Create") { do { try model.createJournal(name: name); name = "" } catch { model.message = error.localizedDescription } }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    Button("Cancel", role: .cancel) {}
                }
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
                Section("Notebook") {
                    TextField("Name", text: $name).accessibilityIdentifier("notebook.name")
                    TextField("Subtitle", text: $subtitle, axis: .vertical).accessibilityIdentifier("notebook.subtitle")
                }
                Section("Original web appearance") {
                    TextField("Color (#RRGGBB)", text: $color).autocorrectionDisabled().textInputAutocapitalization(.never).accessibilityIdentifier("notebook.color")
                    Picker("Cover pattern", selection: $cover) {
                        ForEach(covers, id: \.self) { Text($0.capitalized).tag($0) }
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
            }.modifier(ChapterScreenSurface()).navigationTitle("Edit notebook")
                .sheet(item:$deletionPlan,onDismiss:{ if deletionCompleted { dismiss() } }) { plan in
                    NotebookDeletionView(plan:plan,onDeleted:{deletionCompleted = true})
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { do { try model.updateJournal(journal, name: name, subtitle: subtitle, color: color, cover: cover); dismiss() } catch { self.error = "Unable to save: " + error.localizedDescription + " Your edits are retained here. Cancel and reopen if this notebook changed on another device." } }
                            .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
                Section("Entries on this day") { ForEach(model.entries.filter { Calendar.current.isDate($0.date, inSameDayAs: day) }) { entry in
                    NavigationLink(entry.title) { EntryDetail(entryID: entry.id) }
                } }
                Section("On this device") { LabeledContent("Entries", value: "\(model.entries.count)")
                    LabeledContent("Writing days", value: "\(Set(model.entries.map { Calendar.current.startOfDay(for: $0.date) }).count)") }
            }.modifier(ChapterScreenSurface()).navigationTitle("Calendar")
        }
    }
}
struct SettingsView: View {
    @EnvironmentObject private var model: VaultModel
    var body: some View {
        NavigationStack {
            Form {
                AppearanceSettings()
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
                    Text("Full rich formatting/structural editing and exact custom-node/math/table rendering, camera/audio/video capture, large media and unsupported playback codecs, templates UI, interviews/AI/transcription, import/export, maps, localization, badges, reminders, vault deletion/rotation and operator tools. The web app remains available for these. This preview is not full parity or an independently audited secure product.")
                }
                Section("Open source") { NavigationLink("Original font licenses") { ChapterFontLicenses() }; Link("Source and AGPL-3.0 license", destination: URL(string: "https://github.com/BubbyWoodz/Chapter")!) }
            }.modifier(ChapterScreenSurface()).navigationTitle("Settings")
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
            Picker("Mode",selection:binding(\.mode)) { ForEach(SharedAppearance.modes,id:\.self) { Text($0.capitalized).tag($0) } }.disabled(!model.appearanceInitialized).accessibilityIdentifier("appearance.mode")
            Picker("Style",selection:binding(\.skin)) { ForEach(SharedAppearance.skins,id:\.self) { Text($0.capitalized).tag($0) } }.disabled(!model.appearanceInitialized).accessibilityIdentifier("appearance.skin")
            Picker("Accent",selection:binding(\.palette)) { ForEach(SharedAppearance.palettes,id:\.self) { Text($0.capitalized).tag($0) } }.disabled(!model.appearanceInitialized).accessibilityIdentifier("appearance.palette")
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
                Picker("Notebook", selection: $notebookID) {
                    Text("Choose a notebook").tag("")
                    ForEach(model.journals) { notebook in Text(notebook.title).tag(notebook.journalID) }
                }.accessibilityIdentifier("move.notebook")
                Text("Moves this entry without changing its original rich content, attachments, labels or creation date. Saved changes sync when your server is reachable.").font(.footnote)
                if let error { Text(error).foregroundStyle(.red).accessibilityIdentifier("move.error") }
            }.modifier(ChapterScreenSurface()).navigationTitle("Move entry")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
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
            .toolbar { ToolbarItem(placement:.cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}
