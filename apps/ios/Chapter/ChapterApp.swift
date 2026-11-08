// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import CoreTransferable
import ChapterCore
import QuickLook

@main struct ChapterApp: App {
    @StateObject private var model = VaultModel()
    @Environment(\.scenePhase) private var phase
    @ViewBuilder private var normalContent: some View {
        if model.unlocked { ChapterTabs().task { await model.runForegroundSync() } } else { ConnectView() }
    }
    @ViewBuilder private var rootContent: some View {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--chapter-native-form-audit-repro") {
            NativeFormAuditReproduction()
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
    var body: some View {
        NavigationStack {
            Form {
                Section { Text("Your journal. Your server.").font(.title2).accessibilityAddTraits(.isHeader).accessibilityIdentifier("connection.heading")
                    Text("Connect directly over your local network or Tailscale. No Chapter account is required.") }
                Section {
                    TextField("Server URL", text: $server).font(.body).fixedSize(horizontal: false, vertical: true).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityLabel("Server URL").accessibilityIdentifier("connection.server")
                    Text("HTTPS with a trusted certificate is required, including on Tailscale. Include your server’s path prefix.").font(.footnote).fixedSize(horizontal: false, vertical: true)
                } header: { Text("Server").foregroundStyle(Color.primary) }
                Section {
                    SecureField("12 words", text: $phrase).font(.body).fixedSize(horizontal: false, vertical: true).accessibilityLabel("12-word recovery phrase").accessibilityIdentifier("connection.phrase").textInputAutocapitalization(.never).autocorrectionDisabled().privacySensitive()
                    Text("The phrase stays on this device and is not saved. A device passcode is required to protect offline journals. Face ID or device authentication protects the local storage key.").font(.footnote).fixedSize(horizontal: false, vertical: true)
                    Button(model.connecting ? "Connecting…" : "Unlock and connect") {
                        guard !model.connecting else { return }
                        guard !server.isEmpty, !phrase.isEmpty else {
                            model.message = "Enter your server URL and recovery phrase."; return
                        }
                        let input = phrase; phrase = ""
                        Task { await model.unlock(server: server, phrase: input) }
                    }.buttonStyle(.automatic).tint(Color.primary)
                        .disabled(model.connecting).accessibilityIdentifier("connection.unlock")
                } header: { Text("Unlock vault").foregroundStyle(Color.primary) }
                if let message = model.message { Section { Text(message).accessibilityLabel("Connection status: \(message)").accessibilityIdentifier("connection.status") } }
                Section { Text("This is an early native client, not full feature parity yet. Rich edits preserve the original document; formatted text-run/task editing and file/photo attachments up to 128 MiB are available. Full structural editing and capture remain in development. Use the web client for recovery-phrase creation/rotation and advanced features.") } header: { Text("Native preview").foregroundStyle(Color.primary) }
            }.navigationTitle("Chapter").scrollDismissesKeyboard(.interactively)
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
        }
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
                        Text(entry.title).font(.headline)
                        Text(entry.text).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                        Text(entry.date, format: .dateTime.month().day().year()).font(.caption).foregroundStyle(.secondary)
                    }
                }}
            }
            .navigationTitle("Journal").searchable(text: $query, prompt: "Search this device")
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
    @State private var deleting = false
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
                        Text(entry.title).font(.largeTitle).accessibilityAddTraits(.isHeader)
                        Text(entry.date, style: .date).foregroundStyle(.secondary)
                        if let raw = entry.body["bodyJson"]?.string, let document = try? RichDocument(json: raw) {
                            RichDocumentView(entry: entry, document: document)
                        } else { Text(entry.text).textSelection(.enabled) }
                        let labels = entry.labels
                        if !labels.isEmpty { Text(labels.joined(separator: " · ")).font(.caption) }
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
                            }.disabled(loadingMedia != nil)
                        }
                        if model.canImportMedia, entry.body["bodyJson"]?.string != nil {
                            Button { importSession = model.mediaSession; importingFile = true } label: { Label("Attach file", systemImage: "doc.badge.plus") }
                                .disabled(importingMedia).accessibilityHint("Files up to 128 MiB; saved encrypted before sync")
                            PhotosPicker(selection: $photoSelection, matching: .images) { Label("Attach photo", systemImage: "photo.badge.plus") }.disabled(importingMedia)
                            if importingMedia { ProgressView("Encrypting attachment") }
                            if !(model.snapshot.mediaUploads ?? []).isEmpty { Text("Attachments waiting to upload: \(model.snapshot.mediaUploads?.count ?? 0). Their entry references are not sent until upload completes.").font(.footnote) }
                        }
                        if let mediaError { Text(mediaError).font(.footnote).foregroundStyle(.red) }
                        if !entry.editablePlainText { Text("Rich structure is preserved. Native editing currently changes individual text runs and task state; use the web app for structural or formatting changes.").font(.footnote).foregroundStyle(.secondary) }
                    }.padding().frame(maxWidth: .infinity, alignment: .leading)
                }
                .toolbar {
                    if entry.editablePlainText || (entry.body["bodyJson"]?.string.flatMap { (try? RichDocument(json: $0))?.textLeaves.isEmpty } == false) { Button("Edit") { editing = true } }
                    Button(role: .destructive) { deleting = true } label: { Label("Delete entry", systemImage: "trash") }
                }
                .sheet(isPresented: $editing) {
                    if entry.editablePlainText { EntryEditor(existing: entry, journal: entry.journalID) }
                    else if let raw = entry.body["bodyJson"]?.string, let document = try? RichDocument(json: raw) { RichEntryEditor(entry: entry, document: document) }
                }
                .confirmationDialog("Delete this entry on all synced devices?", isPresented: $deleting, titleVisibility: .visible) {
                    Button("Delete entry", role: .destructive) { do { try model.deleteEntry(entry); dismiss() } catch { model.message = error.localizedDescription } }
                }
            } else { Text("This entry is no longer available.") }
        }.navigationTitle("Entry").navigationBarTitleDisplayMode(.inline).quickLookPreview($previewURL)
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
    let existing: VaultRecord?
    let journal: String
    @State private var title: String
    @State private var text: String
    @State private var labels: String
    @State private var date: Date
    @State private var error: String?
    @State private var savedID: String?
    init(existing: VaultRecord? = nil, journal: String) {
        self.existing = existing; self.journal = journal
        _title = State(initialValue: existing?.title ?? "")
        _text = State(initialValue: existing?.text ?? "")
        _labels = State(initialValue: existing?.labels.joined(separator: ", ") ?? "")
        _date = State(initialValue: existing?.date ?? Date())
        _savedID = State(initialValue: existing?.id)
    }
    private func save() {
        // Every change is durably encrypted before displaying Saved. New drafts keep one ID.
        do {
            let current = savedID.flatMap { id in model.snapshot.records.first { $0.id == id } }
            savedID = try model.saveEntry(existing: current, title: title, text: text, labels: labels, date: date, journal: journal)
            error = nil
        } catch { self.error = error.localizedDescription }
    }
    var body: some View {
        NavigationStack {
            Form {
                TextField("Title", text: $title).accessibilityLabel("Entry title")
                DatePicker("Entry date", selection: $date)
                TextField("Labels, separated by commas", text: $labels)
                Section("Writing") { TextEditor(text: $text).frame(minHeight: 260).accessibilityLabel("Journal text") }
                if let error { Text(error).foregroundStyle(.red) } else { Text(savedID == nil ? "Start writing to save an encrypted draft." : "Saved encrypted on this device.").font(.footnote) }
            }.navigationTitle(existing == nil ? "New entry" : "Edit entry")
            .toolbar { Button("Done") { save(); if error == nil { dismiss() } } }
            .onChange(of: title) { _, _ in save() }.onChange(of: text) { _, _ in save() }
            .onChange(of: labels) { _, _ in save() }.onChange(of: date) { _, _ in save() }
            .interactiveDismissDisabled(error != nil)
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
                        VStack(alignment: .leading) { Text(journal.title)
                            if let subtitle = journal.body["subtitle"]?.string, !subtitle.isEmpty { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                    Button { editing = journal } label: { Image(systemName: "pencil").frame(minWidth: 44, minHeight: 44) }
                        .buttonStyle(.borderless).accessibilityLabel("Edit notebook " + journal.title)
                }
            } }
                .sheet(item: $editing) { NotebookEditor(journal: $0) }
                .navigationTitle("Notebooks").toolbar { Button { adding = true } label: { Label("New notebook", systemImage: "plus") } }
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
                    }
                    Text("These settings sync to the original web client. They do not change the system-native iOS theme. Photo preserves the original cover style; this does not upload a cover image.").font(.footnote)
                }
                if let error { Section { Text(error).accessibilityIdentifier("notebook.error") } }
            }.navigationTitle("Edit notebook")
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
            }.navigationTitle("Calendar")
        }
    }
}
struct SettingsView: View {
    @EnvironmentObject private var model: VaultModel
    var body: some View {
        NavigationStack {
            Form {
                Section("Sync") {
                    Button { Task { await model.sync() } } label: { if model.syncing { ProgressView("Syncing") } else { Label("Sync now", systemImage: "arrow.triangle.2.circlepath") } }.disabled(model.syncing)
                    LabeledContent("Pending changes", value: "\(model.pending)")
                    if let message = model.message { Text(message).font(.footnote) }
                }
                if !model.snapshot.conflicts.isEmpty {
                    Section("Recovered conflicts") {
                        Text("Divergent versions and unsynced changes are kept here when sync detects a conflict. Restore makes a new entry; neither version is silently discarded.").font(.footnote)
                        ForEach(Array(model.snapshot.conflicts.enumerated()), id: \.offset) { _, record in
                            VStack(alignment: .leading) { Text(record.title).font(.headline); Text(record.text).lineLimit(4)
                                if record.kind == "entry" {
                                    Button("Restore as new entry") { do { try model.restoreConflict(record) } catch { model.message = error.localizedDescription } }
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
                    Text("Full rich formatting/structural editing and exact custom-node/math/table rendering, camera/audio/video capture, large media and unsupported playback codecs, templates UI, interviews/AI/transcription, import/export, maps, themes/localization, badges, reminders, vault deletion/rotation and operator tools. The web app remains available for these. This preview is not full parity or an independently audited secure product.")
                }
                Section("Open source") { Link("Source and AGPL-3.0 license", destination: URL(string: "https://github.com/BubbyWoodz/Chapter")!) }
            }.navigationTitle("Settings")
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
