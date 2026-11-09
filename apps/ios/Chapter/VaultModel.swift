// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
import SwiftUI
import CryptoKit
import ChapterCore

@MainActor final class VaultModel: ObservableObject {
    @Published private(set) var unlocked = false
    @Published private(set) var snapshot = VaultSnapshot()
    @Published private(set) var mediaErrors: [String: String] = [:]
    @Published var message: String?
    @Published private(set) var syncing = false
    @Published private(set) var appearanceInitialized = false
    @Published var connecting = false
    @Published private(set) var lastCompletePullID: UUID?
    private var identity: VaultIdentity?
    private var store: EncryptedSnapshotStore?
    private var relay: Relay?
    private var scheduledSync: Task<Void, Never>?
    private var backoff = SyncBackoff()
    private var mediaFiles: EncryptedMediaFiles?
    private var mediaImport: Task<MediaUpload, Error>?
    private var generation = UUID()
    private var playbackFiles: [URL] = []
    init() {
        // Stale playback is regenerable, never an unsynced journal/outbox.
        if let root = try? EncryptedSnapshotStore.applicationDirectory() {
            for name in ["Playback", "ImportStaging"] { try? FileManager.default.removeItem(at: root.appendingPathComponent(name, isDirectory: true)) }
        }
    }
    #if DEBUG
    func loadPublicRichFixture() throws {
        guard ProcessInfo.processInfo.arguments.contains("--chapter-rich-fixture"), store == nil else { return }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ChapterPublicFixture-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let disk = EncryptedSnapshotStore(directory: directory, namespace: "public-fixture-only", key: SymmetricKey(data: Data(repeating: 7, count: 32)))
        var value = VaultSnapshot()
        value.records = [VaultRecord(id: "public-notebook-record", clock: 1, body: ["kind": .string("journal"), "journalId": .string("public-notebook"), "name": .string("Public notebook"), "subtitle": .string("Public subtitle"), "color": .string("#4E8B85"), "cover": .string("lines"), "opaqueFuture": .object(["preserve": .bool(true)])]), VaultRecord(id: "public-rich-fixture", clock: 1, body: ["journalId": .string("public-notebook"), "title": .string("Public rich fixture"), "bodyJson": .string(PublicRichFixture.json), "bodyText": .string(try RichDocument(json: PublicRichFixture.json).plainText)])]
        value.records[1].body["createdAt"] = .number(Date().timeIntervalSince1970 * 1000)
        value.records.append(VaultRecord(id: "public-destination-record", clock: 1, body: ["kind": .string("journal"), "journalId": .string("public-destination"), "name": .string("Public destination"), "color": .string("#B0563A"), "cover": .string("dots")]))
        if ProcessInfo.processInfo.arguments.contains("--chapter-linked-entry-fixture") {
            value.records.append(VaultRecord(id:"entry-target",clock:2,body:["title":.string("Public linked target"),"bodyJson":.string(try VaultRecord.plainDocument("Real local linked-entry navigation")),"bodyText":.string("Real local linked-entry navigation")]))
        }
        if ProcessInfo.processInfo.arguments.contains("--chapter-template-fixture") {
            // PUBLIC synced template shape (kind "template"), like a web user template.
            let json = #"{"type":"doc","content":[{"type":"heading","attrs":{"level":2},"content":[{"type":"text","text":"Public template heading"}]},{"type":"paragraph","content":[{"type":"text","text":"Public template prompt"}]},{"type":"table","content":[{"type":"tableRow","content":[{"type":"tableHeader","content":[{"type":"paragraph","content":[{"type":"text","text":"Public column"}]}]},{"type":"tableHeader","content":[{"type":"paragraph","content":[{"type":"text","text":"Public value"}]}]}]},{"type":"tableRow","content":[{"type":"tableCell","content":[{"type":"paragraph"}]},{"type":"tableCell","content":[{"type":"paragraph"}]}]}]}]}"#
            value.records.append(VaultRecord(id:"public-template",clock:3,body:["kind":.string("template"),"name":.string("Public weekly template"),"bodyJson":.string(json),"bodyText":.string(try RichDocument(json:json).plainText),"createdAt":.number(1),"updatedAt":.number(3)]))
        }
        if ProcessInfo.processInfo.arguments.contains("--chapter-media-fixture") {
            // PUBLIC test identity only; real original crypto and protected local
            // media staging, with NO relay, HTTP fixture or fake server success.
            let publicIdentity = try VaultIdentity(seed:RecoveryPhrase.seed("legal winner thank year wave sausage worth useful legal winner thank yellow"))
            let files = try EncryptedMediaFiles(directory:directory,namespace:"public-fixture-only")
            let source = directory.appendingPathComponent("Public offline note.txt")
            try Data("Public Chapter offline media fixture. This file was genuinely encrypted, queued and decrypted locally. No network authentication or upload is claimed.".utf8).write(to:source,options:.completeFileProtection)
            defer { try? FileManager.default.removeItem(at:source) }
            let upload = try files.stage(source:source,id:String(repeating:"a",count:32),name:"Public offline note",mime:"text/plain",key:publicIdentity.mediaKey)
            try value.attach(upload,entryID:"public-rich-fixture",expectedDocument:PublicRichFixture.json)
            identity = publicIdentity; mediaFiles = files
        }
        try disk.save(value); store = disk; snapshot = value; unlocked = true; appearanceInitialized = true
        // Never creates a relay or pretends to authenticate. Default rich fixture
        // still has no identity; optional media fixture uses public local keys.
    }
    #endif
    var entries: [VaultRecord] { snapshot.records.filter { $0.kind == "entry" && !$0.deleted }.sorted { $0.date > $1.date } }
    var journals: [VaultRecord] { snapshot.records.filter { $0.kind == "journal" && !$0.deleted }.sorted { $0.title < $1.title } }
    var templates: [VaultRecord] { snapshot.records.filter { $0.kind == "template" && !$0.deleted } }
    var mediaSession: UUID { generation }
    var canSync: Bool { relay != nil && identity != nil }
    var canImportMedia: Bool { identity != nil && mediaFiles != nil }
    var pending: Int { snapshot.records.filter(\.dirty).count + (snapshot.mediaUploads?.count ?? 0) }

    func unlock(server: String, phrase: String) async {
        guard !connecting else { return }
        connecting = true; message = nil
        let attempt = generation
        defer { if attempt == generation { connecting = false } }
        do {
            let address = try ServerAddress(server)
            let id = try VaultIdentity(seed: RecoveryPhrase.seed(phrase))
            let disk = try EncryptedSnapshotStore.open(server: address.url, owner: id.ownerID)
            let local = try disk.load()
            guard attempt == generation else { return }
            let files = try EncryptedMediaFiles(directory: EncryptedSnapshotStore.applicationDirectory(), namespace: disk.namespace)
            mediaFiles = files; identity = id; store = disk; snapshot = local; relay = Relay(address: address); unlocked = true; appearanceInitialized = local.appearanceRecord != nil
            UserDefaults.standard.set(address.url.absoluteString, forKey: "chapter.server")
            await sync()
        } catch { if attempt == generation { message = error.localizedDescription } }
    }
    func lock() {
        generation = UUID(); scheduledSync?.cancel(); scheduledSync = nil; backoff = SyncBackoff(); mediaErrors = [:]; mediaImport?.cancel(); mediaImport = nil; mediaFiles = nil; playbackFiles.forEach { try? FileManager.default.removeItem(at: $0) }; playbackFiles = []; relay?.cancel(); relay = nil; identity = nil; store = nil
        if let root = try? EncryptedSnapshotStore.applicationDirectory() { try? FileManager.default.removeItem(at: root.appendingPathComponent("ImportStaging", isDirectory: true)) }
        snapshot = VaultSnapshot(); lastCompletePullID = nil; appearanceInitialized = false; unlocked = false; syncing = false; connecting = false; message = nil
    }
    private func commit(_ next: VaultSnapshot) throws {
        guard let store else { throw ChapterError.storage }
        try store.save(next); snapshot = next
    }
    func saveAppearance(_ preference: SharedAppearance) throws {
        guard unlocked, appearanceInitialized else { throw ChapterError.storage }
        var next=snapshot; try next.setAppearance(preference); try commit(next); scheduleSync()
    }
    private func scheduleSync() {
        scheduledSync?.cancel()
        scheduledSync = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 2_000_000_000) } catch { return }
            guard !Task.isCancelled, let self else { return }
            self.scheduledSync = nil // A later edit must not cancel an in-flight upload.
            await self.sync()
        }
    }
    func runForegroundSync() async {
        while !Task.isCancelled && unlocked {
            await sync()
            guard !Task.isCancelled && unlocked else { return }
            let seconds = backoff.seconds
            do { try await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000) } catch { return }
        }
    }
    func sync() async {
        guard !syncing, let relay, let identity else { return }
        syncing = true; message = nil
        let attempt = generation
        defer { if attempt == generation { syncing = false } }
        do {
            let token = try await relay.authenticate(identity)
            guard attempt == generation else { return }
            var pages = 0
            while true {
                let page = try await relay.pull(since: snapshot.cursor, token: token)
                guard attempt == generation else { return }
                var next = snapshot
                for wire in page.entries {
                    guard let data = Data(base64Encoded: wire.ciphertext) else { throw ChapterError.corruptData }
                    let plain = try VaultCipher.openRecord(data, key: identity.dataKey, id: wire.entry_id)
                    let body = try JSONDecoder().decode([String: JSONValue].self, from: plain)
                    next.merge(VaultRecord(id: wire.entry_id, clock: wire.lww_clock, deleted: wire.deleted, body: body))
                }
                next.cursor = page.cursor
                try commit(next) // content and cursor reach disk together before cursor advances
                if !page.more { break }
                pages += 1; guard pages < 10_000 else { throw ChapterError.corruptData }
            }
            lastCompletePullID = UUID()
            appearanceInitialized = true // Never bootstrap unseen server AI settings while offline.
            try await repairInterruptedMediaRemovals(relay:relay,identity:identity,token:token,attempt:attempt)
            guard attempt == generation else { return }
            var uploadFailed = false
            if let mediaFiles {
                for upload in snapshot.mediaUploads ?? [] {
                    guard snapshot.liveMediaUploadIDs.contains(upload.id) else {
                        mediaErrors[upload.id] = "Paused: retained encrypted for deleted/recovered writing. Restore a referencing entry to upload."
                        continue
                    }
                    do {
                        try await relay.uploadMedia(upload, files: mediaFiles, mediaKey: identity.mediaKey, token: token)
                        guard attempt == generation else { return }
                        var next = snapshot; next.mediaUploaded(upload); try commit(next); mediaErrors.removeValue(forKey: upload.id)
                    } catch {
                        guard attempt == generation else { return }
                        uploadFailed = true; mediaErrors[upload.id] = error.localizedDescription
                        // Retain this queue item; unrelated entries may still sync.
                        // Uploadable-record filtering prevents premature references.
                    }
                }
            }
            var queue = SyncPushQueue()
            while true {
                let batch = try queue.next(from: snapshot)
                if batch.isEmpty { break }
                let results = try await relay.push(batch, identity: identity, token: token)
                guard attempt == generation else { return }
                var next = snapshot
                for sent in batch {
                    if results.contains(where: { $0.entry_id == sent.id && $0.applied }) {
                        next.acknowledge(sent)
                    }
                }
                try commit(next)
            }
            if uploadFailed { backoff.failed(); message = "Some attachments could not upload or be authenticated. Their pending references were not sent. Keep this device and retry; do not delete local work." }
            else { backoff.succeeded(); message = pending == 0 ? "Synced with your server." : "\(pending) changes remain on this device. Sync again to retry." }
        } catch { if attempt == generation { backoff.failed(); message = "Offline or unable to sync: \(error.localizedDescription) Local saved changes are retained." } }
    }
    /// No new DELETE is initiated here. Interrupted existing removals that now
    /// encounter references/unknown work restore original ciphertext BEFORE any
    /// fresh referencing entry is published. Persist repair first; lock or errors
    /// retain the intent/cache and retry on the next authenticated full pull.
    private func repairInterruptedMediaRemovals(relay:Relay,identity:VaultIdentity,token:String,attempt:UUID) async throws {
        guard let mediaFiles else { return }
        for original in try snapshot.mediaPurgeIntents() where original.phase != .queued {
            var needsRepair = original.phase == .repairing
            if !needsRepair {
                do { try snapshot.requireMediaPurgeUnreferenced(original.media) }
                catch { needsRepair = true }
            }
            guard needsRepair else { continue }
            var next=snapshot;let repairing=try next.beginMediaPurgeRepair(original);try commit(next)
            let receipt=try await relay.repairMediaForPurge(repairing,files:mediaFiles,mediaKey:identity.mediaKey,token:token)
            guard attempt == generation else { return }
            next=snapshot;try next.finishMediaPurgeRepair(repairing,receipt:receipt);try commit(next)
            mediaErrors.removeValue(forKey:repairing.media.id)
        }
    }
    private func nextClock(after clock: Int64 = 0) throws -> Int64 {
        try ProtocolNumbers.nextClock(after: clock)
    }
    func saveEntry(existing: VaultRecord?, title: String, text: String, labels: String, date: Date, journal: String, recovery: PlainEntryDraft? = nil) throws -> VaultRecord {
        guard let identity, existing == nil || existing!.editablePlainText else { throw ChapterError.unsupported }
        if let existing {
            guard let live = snapshot.records.first(where: { $0.id == existing.id }), !live.deleted else { throw ChapterError.conflict }
            try live.requiringUnchanged(expected: existing)
        }
        _ = identity // refuses editing while locked
        let clock = try nextClock(after: existing?.clock ?? 0)
        let id = existing?.id ?? UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        var body = existing?.body ?? [:]
        body["title"] = .string(title); body["bodyText"] = .string(text)
        body["bodyJson"] = .string(try VaultRecord.plainDocument(text))
        if let labelValue = try EntryLabels.plainFieldValue(labels,original:existing ?? recovery?.expected) { body["labels"] = labelValue }
        else { body.removeValue(forKey:"labels") }
        body["journalId"] = .string(journal)
        body["createdAt"] = .number(date.timeIntervalSince1970 * 1000); body["updatedAt"] = .number(Double(clock))
        body["chapterNativePlain"] = .bool(true)
        let record = VaultRecord(id: id, clock: clock, body: body, dirty: true)
        var next = snapshot
        // Brand-new vaults need notebook metadata in the same atomic snapshot.
        if journal == "default" && !next.records.contains(where: { $0.kind == "journal" && $0.journalID == journal }) {
            let notebook: [String: JSONValue] = ["kind": .string("journal"), "journalId": .string(journal), "name": .string("Journal"), "subtitle": .string(""), "color": .string("#62564a"), "cover": .string("plain"), "createdAt": .number(Double(clock)), "updatedAt": .number(Double(clock))]
            next.records.append(VaultRecord(id: UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased(), clock: clock, body: notebook, dirty: true))
        }
        if let index = next.records.firstIndex(where: { $0.id == id }) { next.records[index] = record } else { next.records.append(record) }
        if let recovery { try next.finishPlainDraft(recovery) }
        try commit(next); scheduleSync(); return record
    }
    func keepPlainDraft(_ draft: PlainEntryDraft) throws -> PlainEntryDraft {
        guard unlocked else { throw ChapterError.storage }
        var next = snapshot; let saved = try next.keepPlainDraft(draft)
        try commit(next); return saved
    }
    func applyPlainDraft(_ draft: PlainEntryDraft, asNew: Bool = false) throws -> VaultRecord {
        try draft.validate()
        guard draft.journal == "default" || journals.contains(where: { $0.journalID == draft.journal }) else { throw ChapterError.conflict }
        return try saveEntry(existing: asNew ? nil : draft.expected, title: draft.title, text: draft.text, labels: draft.labels, date: draft.date, journal: draft.journal, recovery: draft)
    }
    func saveRichDraft(_ draft: RichDraft) throws {
        var next = snapshot; var drafts = next.richDrafts ?? []
        if let i = drafts.firstIndex(where: { $0.id == draft.id }) { drafts[i] = draft } else { drafts.append(draft) }
        next.richDrafts = drafts; try commit(next)
    }
    func applyRichDraft(_ draft: RichDraft) throws {
        var next = snapshot
        guard let i = next.records.firstIndex(where: { $0.id == draft.entryID }) else { throw ChapterError.conflict }
        next.records[i] = try draft.applying(to: next.records[i])
        next.richDrafts = (next.richDrafts ?? []).filter { $0.id != draft.id }
        try commit(next); scheduleSync()
    }
    func reorderRichBlocks(_ expected: VaultRecord, from offsets: IndexSet, to destination: Int) throws -> VaultRecord {
        guard unlocked else { throw ChapterError.storage }
        var next = snapshot
        let saved = try next.reorderRichBlocks(expected: expected, from: offsets, to: destination)
        try commit(next); scheduleSync(); return saved
    }
    /// Inserts the original web entryLink node. Compare-and-set on the exact
    /// document bytes seen when the picker opened; a concurrent edit refuses.
    func addEntryLink(_ expected: VaultRecord, to targetID: String) throws {
        guard unlocked else { throw ChapterError.storage }
        var next = snapshot
        guard let raw = expected.body["bodyJson"]?.string, let i = next.records.firstIndex(where: { $0.id.utf8.elementsEqual(expected.id.utf8) }),
              let target = next.records.first(where: { $0.kind == "entry" && !$0.deleted && $0.id.utf8.elementsEqual(targetID.utf8) }) else { throw ChapterError.conflict }
        next.records[i] = try next.records[i].addingEntryLink(to: target, expected: raw)
        try commit(next); scheduleSync()
    }
    /// Original web "Use template": a new entry carrying the template's exact
    /// stored bodyJson/bodyText. Uses the live template, never a stale copy.
    func newEntryFromTemplate(_ template: VaultRecord, journalID: String) throws -> VaultRecord {
        guard unlocked else { throw ChapterError.storage }
        guard journals.contains(where: { $0.journalID == journalID }),
              let live = snapshot.records.first(where: { $0.id.utf8.elementsEqual(template.id.utf8) && $0.kind == "template" && !$0.deleted }) else { throw ChapterError.conflict }
        let entry = try EntryTemplates.newEntry(from: live, journalID: journalID, id: UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased(), clock: try nextClock())
        var next = snapshot; next.records.append(entry)
        try commit(next); scheduleSync(); return entry
    }
    func toggleRichTask(_ entry: VaultRecord, path: [Int]) throws {
        var next = snapshot
        guard let raw = entry.body["bodyJson"]?.string, let i = next.records.firstIndex(where: { $0.id == entry.id }) else { throw ChapterError.conflict }
        next.records[i] = try next.records[i].editingRichDocument(expected: raw) { try $0.toggleTask(at: path) }
        try commit(next); scheduleSync()
    }
    func createJournal(name: String) throws {
        let clock = try nextClock(); let id = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let body: [String: JSONValue] = ["kind": .string("journal"), "journalId": .string(id), "name": .string(name), "subtitle": .string(""), "color": .string("#62564a"), "cover": .string("plain"), "createdAt": .number(Double(clock)), "updatedAt": .number(Double(clock))]
        var next = snapshot; next.records.append(VaultRecord(id: UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased(), clock: clock, body: body, dirty: true))
        try commit(next); scheduleSync()
    }
    func updateEntryMetadata(_ expected: VaultRecord, title: String? = nil, date: Date? = nil, labels: [String]? = nil) throws {
        var next = snapshot
        guard let index = next.records.firstIndex(where: { $0.id == expected.id }) else { throw ChapterError.conflict }
        let edited = try next.records[index].editingEntryMetadata(expected: expected, title: title, date: date, labels: labels)
        guard edited != next.records[index] else { return }
        next.records[index] = edited; try commit(next); scheduleSync()
    }
    func updateJournal(_ expected: VaultRecord, name: String, subtitle: String, color: String, cover: String) throws {
        var next = snapshot
        guard let i = next.records.firstIndex(where: { $0.id == expected.id }) else { throw ChapterError.conflict }
        next.records[i] = try next.records[i].editingJournal(expected: expected,
            name: name == expected.body["name"]?.string ? nil : name,
            subtitle: subtitle == (expected.body["subtitle"]?.string ?? "") ? nil : subtitle,
            color: color == (expected.body["color"]?.string ?? "") ? nil : color,
            cover: cover == (expected.body["cover"]?.string ?? "plain") ? nil : cover)
        try commit(next); scheduleSync()
    }
    func moveEntry(_ expected: VaultRecord, notebookID: String) throws {
        var next = snapshot
        guard let i = next.records.firstIndex(where: { $0.id == expected.id }),
              let target = next.records.first(where: { $0.kind == "journal" && !$0.deleted && $0.journalID == notebookID }) else { throw ChapterError.conflict }
        next.records[i] = try next.records[i].movingEntry(expected: expected, to: target)
        try commit(next); scheduleSync()
    }
    func prepareNotebookDeletion(_ notebook: VaultRecord) throws -> NotebookDeletionPlan {
        try NotebookDeletionPlan(snapshot:snapshot,notebook:notebook)
    }
    func deleteNotebook(_ plan: NotebookDeletionPlan) throws {
        guard !syncing, mediaImport == nil else { throw ChapterError.conflict }
        var next = snapshot; try next.deleteNotebookPreservingRecovery(plan)
        try commit(next); scheduleSync()
    }
    func restoreNotebookDeletion(_ expected: VaultRecord) throws {
        guard !syncing, mediaImport == nil else { throw ChapterError.conflict }
        var next = snapshot; try next.restoreNotebookDeletion(expected)
        try commit(next); scheduleSync()
    }
    func deleteEntry(_ entry: VaultRecord) throws {
        var next = snapshot; try next.deleteEntryPreservingRecovery(expected: entry)
        try commit(next); scheduleSync()
    }
    func restoreConflict(_ record: VaultRecord) throws {
        let copy = try record.restoredEntry(id: UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased())
        var next = snapshot; next.records.append(copy); try commit(next); scheduleSync()
    }
    func importMedia(source: URL, name: String, mime: String, entry: VaultRecord, session: UUID) async throws {
        guard session == generation, let identity, let mediaFiles, mediaImport == nil, let raw = entry.body["bodyJson"]?.string else { throw ChapterError.unsupported }
        let attempt = generation, id = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let key = identity.mediaKey
        let task = Task.detached(priority: .userInitiated) { try mediaFiles.stage(source: source, id: id, name: name, mime: mime, key: key) }
        mediaImport = task
        defer { if attempt == generation { mediaImport = nil } }
        var commitAttempted = false, staged = false
        do {
            let upload = try await task.value; staged = true
            guard attempt == generation else { throw CancellationError() }
            var next = snapshot; try next.attach(upload, entryID: entry.id, expectedDocument: raw)
            commitAttempted = true
            try commit(next); scheduleSync() // outbox + lossless body + clock: one atomic encrypted write
            message = "Attachment saved encrypted on this device. Sync uploads media before its entry."
        } catch {
            // Once snapshot save has been attempted it MAY have reached disk even
            // if a later file-attribute operation failed. Never delete its chunks.
            if staged && !commitAttempted { try? mediaFiles.discardUnpublished(id: id) }
            throw error
        }
    }
    func discardPlayback(_ file: URL) {
        guard playbackFiles.contains(file) else { return }
        try? FileManager.default.removeItem(at: file); playbackFiles.removeAll { $0 == file }
    }
    func downloadMedia(_ media: VaultMedia) async throws -> URL {
        guard let identity, let mediaFiles else { throw ChapterError.authentication }
        let relay = self.relay // Offline queued/cached media needs NO server request.
        let attempt = generation, maximum = MediaLimits.maximumPlainBytes
        guard media.bytes <= maximum, MediaLimits.validID(media.id) else { throw ChapterError.unsupported }
        let pending = snapshot.mediaUploads?.first { $0.id == media.id }
        let cached = snapshot.mediaCache?.first { $0.id == media.id }
        var token: String?
        let metadata: MediaCache
        if let pending { metadata = MediaCache(id: pending.id, chunks: pending.chunks, cipherBytes: pending.cipherBytes) }
        else if let cached { metadata = cached }
        else {
            guard let relay else { throw ChapterError.authentication }
            let auth = try await relay.authenticate(identity); token = auth
            guard attempt == generation else { throw CancellationError() }
            metadata = try await relay.mediaMetadata(id: media.id, token: auth)
        }
        guard attempt == generation, (1...512).contains(metadata.chunks) else { throw CancellationError() }
        let directory = try EncryptedSnapshotStore.applicationDirectory().appendingPathComponent("Playback", isDirectory: true)
        try EncryptedMediaFiles.protectedDirectory(directory)
        let extensions = ["video/mp4": "mp4", "video/webm": "webm", "video/quicktime": "mov", "audio/mp4": "m4a", "audio/mpeg": "mp3", "audio/ogg": "ogg", "audio/webm": "webm", "image/jpeg": "jpg", "image/png": "png", "image/heic": "heic", "image/webp": "webp", "application/pdf": "pdf", "text/plain": "txt"]
        let file = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension(extensions[media.mime] ?? "bin")
        guard FileManager.default.createFile(atPath: file.path, contents: nil, attributes: [.protectionKey: FileProtectionType.complete]) else { throw ChapterError.storage }
        playbackFiles.append(file)
        let handle = try FileHandle(forWritingTo: file)
        var succeeded = false
        defer { try? handle.close(); if !succeeded { discardPlayback(file) } }
        var written = 0, cipherBytes: Int64 = 0
        for index in 0..<metadata.chunks {
            let cipher: Data
            if let token {
                guard let relay else { throw ChapterError.authentication }
                cipher = try await relay.mediaChunk(id: media.id, index: index, token: token)
            }
            else { cipher = try mediaFiles.read(id: media.id, index: index) }
            guard attempt == generation else { throw CancellationError() }
            let plain = try VaultCipher.openMediaChunk(cipher, key: identity.mediaKey, id: media.id, index: index, total: metadata.chunks)
            guard plain.count <= 1 << 20, written <= maximum - plain.count else { throw ChapterError.corruptData }
            if token != nil { try mediaFiles.writeDownloaded(cipher, id: media.id, index: index) }
            try handle.write(contentsOf: plain); written += plain.count; cipherBytes += Int64(cipher.count)
        }
        guard (media.bytes == 0 || written == media.bytes), cipherBytes == metadata.cipherBytes else { throw ChapterError.corruptData }
        try handle.synchronize()
        if token != nil {
            var next = snapshot; var cache = next.mediaCache ?? []; cache.removeAll { $0.id == media.id }; cache.append(metadata)
            next.mediaCache = cache; try commit(next)
        }
        succeeded = true; return file
    }
}
