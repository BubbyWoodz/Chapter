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
    @Published var connecting = false
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
        value.records = [VaultRecord(id: "public-rich-fixture", clock: 1, body: ["title": .string("Public rich fixture"), "bodyJson": .string(PublicRichFixture.json), "bodyText": .string(try RichDocument(json: PublicRichFixture.json).plainText)])]
        try disk.save(value); store = disk; snapshot = value; unlocked = true
        // Deliberately no identity, relay or fake sync/auth result. Tests exercise
        // real encrypted local editing, never production Keychain/server auth.
    }
    #endif
    var entries: [VaultRecord] { snapshot.records.filter { $0.kind == "entry" && !$0.deleted }.sorted { $0.date > $1.date } }
    var journals: [VaultRecord] { snapshot.records.filter { $0.kind == "journal" && !$0.deleted }.sorted { $0.title < $1.title } }
    var templates: [VaultRecord] { snapshot.records.filter { $0.kind == "template" && !$0.deleted } }
    var mediaSession: UUID { generation }
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
            mediaFiles = files; identity = id; store = disk; snapshot = local; relay = Relay(address: address); unlocked = true
            UserDefaults.standard.set(address.url.absoluteString, forKey: "chapter.server")
            await sync()
        } catch { if attempt == generation { message = error.localizedDescription } }
    }
    func lock() {
        generation = UUID(); scheduledSync?.cancel(); scheduledSync = nil; backoff = SyncBackoff(); mediaErrors = [:]; mediaImport?.cancel(); mediaImport = nil; mediaFiles = nil; playbackFiles.forEach { try? FileManager.default.removeItem(at: $0) }; playbackFiles = []; relay?.cancel(); relay = nil; identity = nil; store = nil
        if let root = try? EncryptedSnapshotStore.applicationDirectory() { try? FileManager.default.removeItem(at: root.appendingPathComponent("ImportStaging", isDirectory: true)) }
        snapshot = VaultSnapshot(); unlocked = false; syncing = false; connecting = false; message = nil
    }
    private func commit(_ next: VaultSnapshot) throws {
        guard let store else { throw ChapterError.storage }
        try store.save(next); snapshot = next
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
            if let mediaFiles {
                for upload in snapshot.mediaUploads ?? [] {
                    do {
                        try await relay.uploadMedia(upload, files: mediaFiles, mediaKey: identity.mediaKey, token: token)
                        guard attempt == generation else { return }
                        var next = snapshot; next.mediaUploaded(upload); try commit(next); mediaErrors.removeValue(forKey: upload.id)
                    } catch {
                        guard attempt == generation else { return }
                        mediaErrors[upload.id] = error.localizedDescription
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
            if !mediaErrors.isEmpty { backoff.failed(); message = "Some attachments could not upload or be authenticated. Their pending references were not sent. Keep this device and retry; do not delete local work." }
            else { backoff.succeeded(); message = pending == 0 ? "Synced with your server." : "\(pending) changes remain on this device. Sync again to retry." }
        } catch { if attempt == generation { backoff.failed(); message = "Offline or unable to sync: \(error.localizedDescription) Local saved changes are retained." } }
    }
    private func nextClock(after clock: Int64 = 0) throws -> Int64 {
        try ProtocolNumbers.nextClock(after: clock)
    }
    func saveEntry(existing: VaultRecord?, title: String, text: String, labels: String, date: Date, journal: String) throws -> String {
        guard let identity, existing == nil || existing!.editablePlainText else { throw ChapterError.unsupported }
        _ = identity // refuses editing while locked
        let clock = try nextClock(after: existing?.clock ?? 0)
        let id = existing?.id ?? UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        var body = existing?.body ?? [:]
        body["title"] = .string(title); body["bodyText"] = .string(text)
        body["bodyJson"] = .string(try VaultRecord.plainDocument(text))
        body["labels"] = .array(labels.split(separator: ",").map { .string($0.trimmingCharacters(in: .whitespaces)) })
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
        try commit(next); scheduleSync(); return id
    }
    func saveRichDraft(_ draft: RichDraft) throws {
        var next = snapshot; var drafts = next.richDrafts ?? []
        if let i = drafts.firstIndex(where: { $0.id == draft.id }) { drafts[i] = draft } else { drafts.append(draft) }
        next.richDrafts = drafts; try commit(next)
    }
    func applyRichDraft(_ draft: RichDraft) throws {
        var next = snapshot
        guard let i = next.records.firstIndex(where: { $0.id == draft.entryID }) else { throw ChapterError.conflict }
        next.records[i] = try next.records[i].editingRichDocument(expected: draft.expectedDocument) { try $0.replaceText(at: draft.path, with: draft.text) }
        next.richDrafts = (next.richDrafts ?? []).filter { $0.id != draft.id }
        try commit(next); scheduleSync()
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
    func deleteEntry(_ entry: VaultRecord) throws {
        var next = snapshot
        guard let i = next.records.firstIndex(where: { $0.id == entry.id }) else { return }
        next.records[i].clock = try nextClock(after: entry.clock); next.records[i].deleted = true; next.records[i].dirty = true
        next.records[i].body["updatedAt"] = .number(Double(next.records[i].clock)); try commit(next); scheduleSync()
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
        guard let relay, let identity, let mediaFiles else { throw ChapterError.authentication }
        let attempt = generation, maximum = MediaLimits.maximumPlainBytes
        guard media.bytes <= maximum, MediaLimits.validID(media.id) else { throw ChapterError.unsupported }
        let pending = snapshot.mediaUploads?.first { $0.id == media.id }
        let cached = snapshot.mediaCache?.first { $0.id == media.id }
        var token: String?
        let metadata: MediaCache
        if let pending { metadata = MediaCache(id: pending.id, chunks: pending.chunks, cipherBytes: pending.cipherBytes) }
        else if let cached { metadata = cached }
        else {
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
            if let token { cipher = try await relay.mediaChunk(id: media.id, index: index, token: token) }
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
