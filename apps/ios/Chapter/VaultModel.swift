// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
import SwiftUI
import CryptoKit
import ChapterCore

@MainActor final class VaultModel: ObservableObject {
    @Published private(set) var unlocked = false
    @Published private(set) var snapshot = VaultSnapshot()
    @Published var message: String?
    @Published private(set) var syncing = false
    @Published var connecting = false
    private var identity: VaultIdentity?
    private var store: EncryptedSnapshotStore?
    private var relay: Relay?
    private var generation = UUID()
    private var playbackFiles: [URL] = []
    init() {
        // Stale playback is regenerable, never an unsynced journal/outbox.
        if let root = try? EncryptedSnapshotStore.applicationDirectory() {
            try? FileManager.default.removeItem(at: root.appendingPathComponent("Playback", isDirectory: true))
        }
    }
    var entries: [VaultRecord] { snapshot.records.filter { $0.kind == "entry" && !$0.deleted }.sorted { $0.date > $1.date } }
    var journals: [VaultRecord] { snapshot.records.filter { $0.kind == "journal" && !$0.deleted }.sorted { $0.title < $1.title } }
    var templates: [VaultRecord] { snapshot.records.filter { $0.kind == "template" && !$0.deleted } }
    var pending: Int { snapshot.records.filter(\.dirty).count }

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
            identity = id; store = disk; snapshot = local; relay = Relay(address: address); unlocked = true
            UserDefaults.standard.set(address.url.absoluteString, forKey: "chapter.server")
            await sync()
        } catch { if attempt == generation { message = error.localizedDescription } }
    }
    func lock() {
        generation = UUID(); playbackFiles.forEach { try? FileManager.default.removeItem(at: $0) }; playbackFiles = []; relay?.cancel(); relay = nil; identity = nil; store = nil
        snapshot = VaultSnapshot(); unlocked = false; syncing = false; connecting = false; message = nil
    }
    private func commit(_ next: VaultSnapshot) throws {
        guard let store else { throw ChapterError.storage }
        try store.save(next); snapshot = next
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
            let batch = Array(snapshot.records.filter(\.dirty).prefix(100))
            if !batch.isEmpty {
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
            message = pending == 0 ? "Synced with your server." : "\(pending) changes remain safely on this device. Sync again to retry."
        } catch { if attempt == generation { message = "Offline or unable to sync: \(error.localizedDescription) Local saved changes are retained." } }
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
        try commit(next); return id
    }
    func createJournal(name: String) throws {
        let clock = try nextClock(); let id = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let body: [String: JSONValue] = ["kind": .string("journal"), "journalId": .string(id), "name": .string(name), "subtitle": .string(""), "color": .string("#62564a"), "cover": .string("plain"), "createdAt": .number(Double(clock)), "updatedAt": .number(Double(clock))]
        var next = snapshot; next.records.append(VaultRecord(id: UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased(), clock: clock, body: body, dirty: true))
        try commit(next)
    }
    func deleteEntry(_ entry: VaultRecord) throws {
        var next = snapshot
        guard let i = next.records.firstIndex(where: { $0.id == entry.id }) else { return }
        next.records[i].clock = try nextClock(after: entry.clock); next.records[i].deleted = true; next.records[i].dirty = true
        next.records[i].body["updatedAt"] = .number(Double(next.records[i].clock)); try commit(next)
    }
    func restoreConflict(_ record: VaultRecord) throws {
        let copy = try record.restoredEntry(id: UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased())
        var next = snapshot; next.records.append(copy); try commit(next)
    }
    func downloadMedia(_ media: VaultMedia) async throws -> URL {
        guard let relay, let identity else { throw ChapterError.authentication }
        let attempt = generation
        // Explicit preview action only. Large files are deferred rather than exhausting memory/disk.
        let maximum = 128 * 1024 * 1024
        guard media.bytes <= maximum else { throw ChapterError.unsupported }
        let token = try await relay.authenticate(identity)
        guard attempt == generation else { throw CancellationError() }
        let count = try await relay.mediaChunks(id: media.id, token: token)
        guard attempt == generation else { throw CancellationError() }
        let directory = try EncryptedSnapshotStore.applicationDirectory().appendingPathComponent("Playback", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.complete])
        let extensions = ["video/mp4": "mp4", "video/webm": "webm", "video/quicktime": "mov", "audio/mp4": "m4a", "audio/mpeg": "mp3", "audio/ogg": "ogg", "audio/webm": "webm", "image/jpeg": "jpg", "image/png": "png", "image/heic": "heic", "image/webp": "webp", "application/pdf": "pdf", "text/plain": "txt"]
        let file = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension(extensions[media.mime] ?? "bin")
        guard FileManager.default.createFile(atPath: file.path, contents: nil, attributes: [.protectionKey: FileProtectionType.complete]) else { throw ChapterError.storage }
        playbackFiles.append(file)
        let handle = try FileHandle(forWritingTo: file)
        var succeeded = false
        defer { try? handle.close(); if !succeeded { try? FileManager.default.removeItem(at: file) } }
        var written = 0
        for index in 0..<count {
            let cipher = try await relay.mediaChunk(id: media.id, index: index, token: token)
            guard attempt == generation else { throw CancellationError() }
            let plain = try VaultCipher.openMediaChunk(cipher, key: identity.mediaKey, id: media.id, index: index, total: count)
            guard plain.count <= 1 << 20, written <= maximum - plain.count else { throw ChapterError.corruptData }
            try handle.write(contentsOf: plain); written += plain.count
        }
        guard media.bytes == 0 || written == media.bytes else { throw ChapterError.corruptData }
        try handle.synchronize(); succeeded = true; return file
    }

}
