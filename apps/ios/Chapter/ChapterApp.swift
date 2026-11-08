// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI
import ChapterCore
import QuickLook

@main struct ChapterApp: App {
    @StateObject private var model = VaultModel()
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            ZStack {
                if model.unlocked { ChapterTabs() } else { ConnectView() }
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
                    Button {
                        guard !model.connecting else { return }
                        guard !server.isEmpty, !phrase.isEmpty else {
                            model.message = "Enter your server URL and recovery phrase."; return
                        }
                        let input = phrase; phrase = ""
                        Task { await model.unlock(server: server, phrase: input) }
                    } label: {
                        Text(model.connecting ? "Connecting…" : "Unlock and connect")
                            .font(.body).fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
                    }.buttonStyle(.automatic).tint(Color.primary)
                        .disabled(model.connecting).accessibilityIdentifier("connection.unlock")
                } header: { Text("Unlock vault").foregroundStyle(Color.primary) }
                if let message = model.message { Section { Text(message).accessibilityLabel("Connection status: \(message)").accessibilityIdentifier("connection.status") } }
                Section { Text("This is an early native client, not full feature parity yet. Rich edits preserve the original document; the complete editor and media capture/upload remain in development. Use the web client for recovery-phrase creation/rotation and advanced features.") } header: { Text("Native preview").foregroundStyle(Color.primary) }
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
    var body: some View {
        NavigationStack {
            List { ForEach(model.journals) { journal in NavigationLink(journal.title) { EntryList(journal: journal.journalID) } } }
                .navigationTitle("Notebooks").toolbar { Button { adding = true } label: { Label("New notebook", systemImage: "plus") } }
                .alert("New notebook", isPresented: $adding) {
                    TextField("Name", text: $name)
                    Button("Create") { do { try model.createJournal(name: name); name = "" } catch { model.message = error.localizedDescription } }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    Button("Cancel", role: .cancel) {}
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
                Section("Privacy") {
                    Text("No analytics, ads, cloud account, remote previews or automatic AI requests. Offline records are AES-GCM encrypted with a device-only Keychain key; sync uses the existing XChaCha20 vault protocol. Recovery phrase and sessions are memory-only.")
                    Text("The app locks on background. The phrase is required again to unlock; local-key access may request device authentication. Unsynced drafts remain encrypted on this device.")
                    Button("Lock vault", role: .destructive) { model.lock() }
                }
                Section("Not yet implemented") {
                    Text("Full rich formatting/structural editing and exact custom-node/math/table rendering, media capture/upload and unsupported playback codecs, templates UI, interviews/AI/transcription, import/export, maps, themes/localization, badges, reminders, vault deletion/rotation and operator tools. The web app remains available for these. This preview is not full parity or an independently audited secure product.")
                }
                Section("Open source") { Link("Source and AGPL-3.0 license", destination: URL(string: "https://github.com/BubbyWoodz/Chapter")!) }
            }.navigationTitle("Settings")
        }
    }
}
