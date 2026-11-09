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
    /// Original web language choice: device-only (never synced), English by default.
    @Published private(set) var localeID: String = UserDefaults.standard.string(forKey: "chapter.locale") ?? "en"
    var language: ChapterLocale? { ChapterLocales.bundled.map { ChapterLocales.resolve(stored: localeID, in: $0) } }
    /// The web's own interface text (src/i18n catalogs) in the chosen language.
    func t(_ key: String, _ params: [String: String] = [:]) -> String { ChapterStrings.bundled.t(key, params, locale: localeID) }
    func tp(_ base: String, count: Int, _ params: [String: String] = [:]) -> String { ChapterStrings.bundled.tp(base, count: Double(count), params, locale: localeID) }
    func setLanguage(_ id: String) {
        guard let catalog = ChapterLocales.bundled, catalog.locales.contains(where: { $0.id == id }) else { return }
        localeID = id; UserDefaults.standard.set(id, forKey: "chapter.locale")
    }
    @Published private(set) var lastCompletePullID: UUID?
    // Web useBadges: the celebration queue and the device-local celebrated set per owner.
    @Published private(set) var badgeQueue: [String] = []
    private var badgeSeen: Set<String>?
    private var badgeOwner: String?
    var earnedBadges: Set<String> {
        ChapterBadges.evaluate(ChapterBadges.entries(snapshot.records.filter { $0.kind == "entry" }), interviewTypeNames: ChapterBadges.interviewTypeNames(snapshot.records, name: { self.t($0) }))
    }
    /// Evaluate only once hydrated: after the first complete pull (or with no relay at all),
    /// so the empty→loaded transition never reads as "everything newly earned".
    func refreshBadges() {
        guard unlocked, let owner = identity?.ownerID, relay == nil || lastCompletePullID != nil else { return }
        if badgeOwner != owner { badgeOwner = owner; badgeSeen = nil; badgeQueue = [] }
        let key = ChapterBadges.seenKey(owner), earned = earnedBadges
        let seen = badgeSeen ?? ChapterBadges.loadSeen(UserDefaults.standard.string(forKey: key))
        let result = ChapterBadges.catchUpOrDelta(seen: seen, earned: earned)
        badgeSeen = result.seen
        if seen == nil { UserDefaults.standard.set(ChapterBadges.encodeSeen(result.seen), forKey: key); return }
        badgeQueue += result.celebrate.filter { !badgeQueue.contains($0) }
        badgeQueue = badgeQueue.filter(earned.contains)
    }
    func dismissBadgeCelebration() {
        guard let current = badgeQueue.first, let owner = badgeOwner else { return }
        var seen = badgeSeen ?? []; seen.insert(current); badgeSeen = seen
        UserDefaults.standard.set(ChapterBadges.encodeSeen(seen), forKey: ChapterBadges.seenKey(owner))
        badgeQueue.removeFirst()
    }
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
            for name in ["Playback", "ImportStaging", "Exports"] { try? FileManager.default.removeItem(at: root.appendingPathComponent(name, isDirectory: true)) }
        }
    }
    #if DEBUG
    /// A PUBLIC Day One JSON export built on the device for the import UI test: one notebook,
    /// a two-photo gallery entry and an entry whose photo is missing from the export.
    func publicDayOneFixture() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("public-dayone-\(UUID().uuidString).zip")
        let journal = ##"{"metadata":{"version":"1.0"},"entries":[{"uuid":"PUBLIC1","creationDate":"2024-05-01T10:00:00Z","text":"# Public Lisbon\n\n![](dayone-moment://P1)\n![](dayone-moment://P2)\n\nWalked to the river.","tags":["public"],"photos":[{"identifier":"P1","md5":"p1","type":"png","width":2,"height":2},{"identifier":"P2","md5":"p2","type":"png"}]},{"uuid":"PUBLIC2","creationDate":"2024-05-02T10:00:00Z","text":"Public second day\n![](dayone-moment://GONE)","photos":[{"identifier":"GONE","md5":"gone","type":"jpeg"}]}]}"##
        let writer = try ChapterZipWriter(url: url, fallbackMtime: Date().timeIntervalSince1970 * 1000)
        try writer.add(path: "Public Day One trip.json", data: Data(journal.utf8), mtime: nil)
        try writer.add(path: "photos/p1.png", data: Data("public photo one".utf8), mtime: nil)
        try writer.add(path: "photos/p2.png", data: Data("public photo two".utf8), mtime: nil)
        try writer.finish()
        return url
    }
    func loadPublicRichFixture() throws {
        guard ProcessInfo.processInfo.arguments.contains("--chapter-rich-fixture"), store == nil else { return }
        // Public fixtures always start in English, so a language chosen by one UI test never leaks into another.
        UserDefaults.standard.removeObject(forKey: "chapter.locale"); localeID = "en"
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
        if ProcessInfo.processInfo.arguments.contains("--chapter-location-fixture") {
            // A PUBLIC drawn map image, genuinely encrypted into the protected local media
            // queue with the public test identity; the card decrypts it offline.
            let publicIdentity = try identity ?? VaultIdentity(seed:RecoveryPhrase.seed("legal winner thank year wave sausage worth useful legal winner thank yellow"))
            let files = try mediaFiles ?? EncryptedMediaFiles(directory:directory,namespace:"public-fixture-only")
            let png = UIGraphicsImageRenderer(size:CGSize(width:600,height:340)).pngData { context in
                UIColor(red:0.91,green:0.89,blue:0.84,alpha:1).setFill(); context.fill(CGRect(x:0,y:0,width:600,height:340))
                UIColor(red:0.31,green:0.55,blue:0.52,alpha:1).setStroke(); let road=UIBezierPath(); road.move(to:CGPoint(x:60,y:280)); road.addCurve(to:CGPoint(x:540,y:70),controlPoint1:CGPoint(x:260,y:300),controlPoint2:CGPoint(x:330,y:60)); road.lineWidth=10; road.stroke()
            }
            let source = directory.appendingPathComponent("Public map.png"); try png.write(to:source,options:.completeFileProtection)
            defer { try? FileManager.default.removeItem(at:source) }
            let upload = try files.stage(source:source,id:String(repeating:"b",count:32),name:"Public map",mime:"image/png",key:publicIdentity.mediaKey)
            try upload.validate()
            let json = #"{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":"Public walk"}]},{"type":"locationMap","attrs":{"from":{"lat":48.8566,"lng":2.3522,"label":"Musée"},"to":{"lat":48.8606,"lng":2.3376,"label":""},"zoom":14,"map":{"id":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","mime":"image/png","bytes":\#(png.count),"width":600,"height":340,"createdAt":1}}}]}"#
            value.records.append(VaultRecord(id:"public-location-entry",clock:2,body:["journalId":.string("public-notebook"),"title":.string("Public location card"),"bodyJson":.string(json),"bodyText":.string(try RichDocument(json:json).plainText),"createdAt":.number(Date().timeIntervalSince1970 * 1000 + 1)]))
            value.mediaUploads = (value.mediaUploads ?? []) + [upload]
            identity = publicIdentity; mediaFiles = files
        }
        if let fixtureLocale = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--chapter-fixture-locale=") })?.dropFirst("--chapter-fixture-locale=".count) { setLanguage(String(fixtureLocale)) }
        if let owner = identity?.ownerID {
            // Public fixtures start from the quiet first-run catch-up so a celebration never
            // covers another test; --chapter-fixture-badges-unseen celebrates everything earned.
            let key = ChapterBadges.seenKey(owner)
            if ProcessInfo.processInfo.arguments.contains("--chapter-fixture-badges-unseen") { UserDefaults.standard.set("[]", forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) }
        }
        try disk.save(value); store = disk; snapshot = value; unlocked = true; appearanceInitialized = true
        // Never creates a relay or pretends to authenticate. Default rich fixture
        // still has no identity; optional media fixture uses public local keys.
    }
    #endif
    var entries: [VaultRecord] { snapshot.records.filter { $0.kind == "entry" && !$0.deleted }.sorted { $0.date > $1.date } }
    var journals: [VaultRecord] { snapshot.records.filter { $0.kind == "journal" && !$0.deleted }.sorted { $0.title < $1.title } }
    var templates: [VaultRecord] { snapshot.records.filter { $0.kind == "template" && !$0.deleted } }
    /// Original web pristine built-in seeds not yet superseded by a synced copy.
    /// Shown in the active language, like the web's localizeBuiltinTemplate.
    var builtinTemplates: [BuiltinTemplate] { BuiltinTemplates.pristine(ChapterLocales.bundled.map { ChapterLocales.seeds(for: localeID, in: $0) } ?? BuiltinTemplates.bundled, records: snapshot.records) }
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
        generation = UUID(); scheduledSync?.cancel(); scheduledSync = nil; backoff = SyncBackoff(); mediaErrors = [:]; mediaImport?.cancel(); mediaImport = nil; mediaFiles = nil; playbackFiles.forEach { try? FileManager.default.removeItem(at: $0) }; playbackFiles = []; discardExports(); exportProgress = nil; relay?.cancel(); relay = nil; identity = nil; store = nil
        if let root = try? EncryptedSnapshotStore.applicationDirectory() { try? FileManager.default.removeItem(at: root.appendingPathComponent("ImportStaging", isDirectory: true)) }
        snapshot = VaultSnapshot(); seedForks = [:]; badgeQueue = []; badgeSeen = nil; badgeOwner = nil; lastCompletePullID = nil; appearanceInitialized = false; unlocked = false; syncing = false; connecting = false; message = nil
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
    /// Built-in body editing (web mutateSeeded on first change): the fork exists only
    /// in memory until a change is applied, then joins the snapshot in that same commit.
    /// Opening and closing the editor without a change creates and syncs nothing.
    @Published private(set) var seedForks: [String: VaultRecord] = [:]
    func prepareSeedEdit(_ seed: BuiltinTemplate) throws -> VaultRecord {
        let live = try liveSeed(seed)
        if let open = seedForks.values.first(where: { $0.body["builtin"]?.string == live.slug && $0.body["bodyJson"] == .string(live.bodyJson) }) { return open }
        let fork = try BuiltinTemplates.fork(live, id: UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased(), clock: try nextClock())
        seedForks[fork.id] = fork; return fork
    }
    /// The live record an editor works on: a stored entry/template, or a prepared seed fork.
    func editableRecord(_ id: String) -> VaultRecord? {
        snapshot.records.first { $0.id.utf8.elementsEqual(id.utf8) && !$0.deleted && ($0.kind == "entry" || $0.kind == "template") } ?? seedForks[id]
    }
    private func materializeSeedFork(_ next: inout VaultSnapshot, _ id: String) {
        guard !next.records.contains(where: { $0.id.utf8.elementsEqual(id.utf8) }), let fork = seedForks[id] else { return }
        next.records.append(fork)
    }
    private func seedForkCommitted(_ id: String) { if snapshot.records.contains(where: { $0.id == id }) { seedForks[id] = nil } }
    func saveRichDraft(_ draft: RichDraft) throws {
        var next = snapshot; var drafts = next.richDrafts ?? []
        if let i = drafts.firstIndex(where: { $0.id == draft.id }) { drafts[i] = draft } else { drafts.append(draft) }
        next.richDrafts = drafts; try commit(next)
    }
    func applyRichDraft(_ draft: RichDraft) throws {
        var next = snapshot; materializeSeedFork(&next, draft.entryID)
        guard let i = next.records.firstIndex(where: { $0.id == draft.entryID }) else { throw ChapterError.conflict }
        next.records[i] = try draft.applying(to: next.records[i])
        next.richDrafts = (next.richDrafts ?? []).filter { $0.id != draft.id }
        try commit(next); seedForkCommitted(draft.entryID); scheduleSync()
    }
    func reorderRichBlocks(_ expected: VaultRecord, from offsets: IndexSet, to destination: Int) throws -> VaultRecord {
        guard unlocked else { throw ChapterError.storage }
        var next = snapshot; materializeSeedFork(&next, expected.id)
        let saved = try next.reorderRichBlocks(expected: expected, from: offsets, to: destination)
        try commit(next); seedForkCommitted(expected.id); scheduleSync(); return saved
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
    /// At-cursor variants of the original wikilink / Editor insertTemplate edits.
    /// Compare-and-set on the exact document bytes the caret was computed from.
    func insertEntryLink(_ expected: VaultRecord, to targetID: String, at caret: RichCaret) throws {
        guard unlocked else { throw ChapterError.storage }
        var next = snapshot
        guard let raw = expected.body["bodyJson"]?.string, let i = next.records.firstIndex(where: { $0.id.utf8.elementsEqual(expected.id.utf8) }),
              let target = next.records.first(where: { $0.kind == "entry" && !$0.deleted && $0.id.utf8.elementsEqual(targetID.utf8) }) else { throw ChapterError.conflict }
        next.records[i] = try next.records[i].insertingEntryLink(to: target, at: caret, expected: raw)
        try commit(next); scheduleSync()
    }
    func applyTableCommand(_ expected: VaultRecord, command: RichTableCommand, table: [Int], row: Int, column: Int) throws {
        guard unlocked else { throw ChapterError.storage }
        var next = snapshot; materializeSeedFork(&next, expected.id)
        guard let raw = expected.body["bodyJson"]?.string, let i = next.records.firstIndex(where: { $0.id.utf8.elementsEqual(expected.id.utf8) }) else { throw ChapterError.conflict }
        next.records[i] = try next.records[i].applyingTableCommand(command, table: table, row: row, column: column, expected: raw)
        try commit(next); seedForkCommitted(expected.id); scheduleSync()
    }
    func toggleSelectionMark(_ expected: VaultRecord, type: String, leaf: [Int], range: Range<Int>) throws {
        guard unlocked else { throw ChapterError.storage }
        var next = snapshot; materializeSeedFork(&next, expected.id)
        guard let raw = expected.body["bodyJson"]?.string, let i = next.records.firstIndex(where: { $0.id.utf8.elementsEqual(expected.id.utf8) }) else { throw ChapterError.conflict }
        next.records[i] = try next.records[i].togglingMark(type, leaf: leaf, utf16Range: range, expected: raw)
        try commit(next); seedForkCommitted(expected.id); scheduleSync()
    }
    /// Original toolbar toggleMark over a selection spanning a paragraph's or heading's runs.
    func toggleRangeMark(_ expected: VaultRecord, type: String, block: [Int], range: Range<Int>) throws {
        guard unlocked else { throw ChapterError.storage }
        var next = snapshot; materializeSeedFork(&next, expected.id)
        guard let raw = expected.body["bodyJson"]?.string, let i = next.records.firstIndex(where: { $0.id.utf8.elementsEqual(expected.id.utf8) }) else { throw ChapterError.conflict }
        next.records[i] = try next.records[i].togglingMark(type, block: block, range: range, expected: raw)
        try commit(next); seedForkCommitted(expected.id); scheduleSync()
    }
    func insertTemplate(_ expected: VaultRecord, template: VaultRecord, at caret: RichCaret) throws {
        guard unlocked else { throw ChapterError.storage }
        var next = snapshot
        guard let raw = expected.body["bodyJson"]?.string, let i = next.records.firstIndex(where: { $0.id.utf8.elementsEqual(expected.id.utf8) }) else { throw ChapterError.conflict }
        let live: VaultRecord
        if let seed = builtinTemplates.first(where: { $0.id == template.id }) { live = seed.seedRecord }
        else if let synced = templates.first(where: { $0.id.utf8.elementsEqual(template.id.utf8) }) { live = synced }
        else { throw ChapterError.conflict }
        next.records[i] = try next.records[i].insertingTemplate(live, at: caret, expected: raw)
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
    /// Original web template manager: create / rename / tombstone, synced like any record.
    @discardableResult func createTemplate(name: String, text: String) throws -> VaultRecord {
        guard unlocked else { throw ChapterError.storage }
        let record = try EntryTemplates.newTemplate(name: name, text: text, id: UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased(), clock: try nextClock())
        var next = snapshot; next.records.append(record)
        try commit(next); scheduleSync(); return record
    }
    private func liveSeed(_ seed: BuiltinTemplate) throws -> BuiltinTemplate {
        guard unlocked else { throw ChapterError.storage }
        guard let live = builtinTemplates.first(where: { $0.slug == seed.slug }) else { throw ChapterError.conflict }
        return live
    }
    func newEntryFromBuiltin(_ seed: BuiltinTemplate, journalID: String) throws -> VaultRecord {
        let live = try liveSeed(seed)
        guard journals.contains(where: { $0.journalID == journalID }) else { throw ChapterError.conflict }
        let entry = try EntryTemplates.newEntry(from: live.seedRecord, journalID: journalID, id: UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased(), clock: try nextClock())
        var next = snapshot; next.records.append(entry)
        try commit(next); scheduleSync(); return entry
    }
    /// Web mutateSeeded: the first rename/delete forks the seed into a synced record.
    func forkBuiltin(_ seed: BuiltinTemplate, name: String? = nil, deleted: Bool = false) throws {
        let live = try liveSeed(seed)
        let record = try BuiltinTemplates.fork(live, id: UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased(), clock: try nextClock(), name: name, deleted: deleted)
        var next = snapshot; next.records.append(record)
        try commit(next); scheduleSync()
    }
    // MARK: Interview types (web InterviewTypesSheet)
    /// Live synced interview types: forked built-ins in built-in order, then the user's own by creation.
    var interviewTypes: [VaultRecord] {
        let order = Dictionary(uniqueKeysWithValues: InterviewTypes.builtins.enumerated().map { ($1.slug, $0) })
        return snapshot.records.filter { $0.kind == "interviewType" && !$0.deleted }.sorted { a, b in
            let oa = a.body["builtin"]?.string.flatMap { order[$0] } ?? Int.max, ob = b.body["builtin"]?.string.flatMap { order[$0] } ?? Int.max
            if oa != ob { return oa < ob }
            let ca = a.body["createdAt"]?.number ?? 0, cb = b.body["createdAt"]?.number ?? 0
            return ca != cb ? ca < cb : a.id < b.id
        }
    }
    var builtinInterviews: [InterviewTypes.Builtin] { InterviewTypes.pristine(records: snapshot.records) }
    private func newRecordID() -> String { UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased() }
    func createInterviewType(name: String, intro: String, prompt: String) throws {
        guard unlocked else { throw ChapterError.storage }
        let c = InterviewTypes.cleaned(name: name, intro: intro, prompt: prompt, untitled: t("assistant.types.untitled"))
        var next = snapshot; next.records.append(try InterviewTypes.newType(name: c.name, intro: c.intro, prompt: c.prompt, id: newRecordID(), clock: try nextClock()))
        try commit(next); scheduleSync()
    }
    func editInterviewType(_ expected: VaultRecord, name: String, intro: String, prompt: String) throws {
        guard unlocked else { throw ChapterError.storage }
        let c = InterviewTypes.cleaned(name: name, intro: intro, prompt: prompt, untitled: t("assistant.types.untitled"))
        var next = snapshot
        guard let i = next.records.firstIndex(where: { $0.id.utf8.elementsEqual(expected.id.utf8) }) else { throw ChapterError.conflict }
        let edited = try next.records[i].editingInterviewType(expected: expected, name: c.name, intro: c.intro, prompt: c.prompt)
        guard edited != next.records[i] else { return }
        next.records[i] = edited; try commit(next); scheduleSync()
    }
    func deleteInterviewType(_ expected: VaultRecord) throws {
        guard unlocked else { throw ChapterError.storage }
        var next = snapshot
        guard let i = next.records.firstIndex(where: { $0.id.utf8.elementsEqual(expected.id.utf8) }) else { throw ChapterError.conflict }
        next.records[i] = try next.records[i].deletingInterviewType(expected: expected)
        try commit(next); scheduleSync()
    }
    /// First edit or delete of a pristine built-in forks it (web mutateSeeded); an unchanged save forks nothing.
    func forkBuiltinInterview(_ seed: InterviewTypes.Builtin, name: String? = nil, intro: String? = nil, prompt: String? = nil, deleted: Bool = false) throws {
        guard unlocked, builtinInterviews.contains(seed) else { throw ChapterError.conflict }
        let shown = (t(seed.nameKey), t(seed.introKey), seed.prompt)
        let c = InterviewTypes.cleaned(name: name ?? shown.0, intro: intro ?? shown.1, prompt: prompt ?? shown.2, untitled: t("assistant.types.untitled"))
        if !deleted && c.name == shown.0 && c.intro == shown.1 && c.prompt == shown.2 { return }
        var next = snapshot; next.records.append(try InterviewTypes.fork(seed, name: c.name, intro: c.intro, prompt: c.prompt, id: newRecordID(), clock: try nextClock(), deleted: deleted))
        try commit(next); scheduleSync()
    }
    func renameTemplate(_ expected: VaultRecord, name: String) throws {
        guard unlocked else { throw ChapterError.storage }
        var next = snapshot
        guard let i = next.records.firstIndex(where: { $0.id.utf8.elementsEqual(expected.id.utf8) }) else { throw ChapterError.conflict }
        let edited = try next.records[i].renamingTemplate(expected: expected, name: name)
        guard edited != next.records[i] else { return }
        next.records[i] = edited; try commit(next); scheduleSync()
    }
    func deleteTemplate(_ expected: VaultRecord) throws {
        guard unlocked else { throw ChapterError.storage }
        var next = snapshot
        guard let i = next.records.firstIndex(where: { $0.id.utf8.elementsEqual(expected.id.utf8) }) else { throw ChapterError.conflict }
        next.records[i] = try next.records[i].deletingTemplate(expected: expected)
        try commit(next); scheduleSync()
    }
    func toggleRichTask(_ entry: VaultRecord, path: [Int]) throws {
        var next = snapshot
        guard let raw = entry.body["bodyJson"]?.string, let i = next.records.firstIndex(where: { $0.id == entry.id }) else { throw ChapterError.conflict }
        next.records[i] = try next.records[i].editingRichDocument(expected: raw) { try $0.toggleTask(at: path) }
        try commit(next); scheduleSync()
    }
    /// Web NewJournalSheet → newJournal: the chosen name, colour and cover; subtitle is t('journals.new').
    @discardableResult func createJournal(name: String, subtitle: String = "", color: String = "#62564a", cover: String = "plain", journalID: String? = nil) throws -> String {
        let clock = try nextClock(); let id = journalID ?? UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let body: [String: JSONValue] = ["kind": .string("journal"), "journalId": .string(id), "name": .string(name), "subtitle": .string(subtitle), "color": .string(color), "cover": .string(cover), "createdAt": .number(Double(clock)), "updatedAt": .number(Double(clock))]
        var next = snapshot; next.records.append(VaultRecord(id: UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased(), clock: clock, body: body, dirty: true))
        try commit(next); scheduleSync()
        return id
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
    // MARK: Day One import (web ImportDayOne → parseDayOneArchive + importDayOne)
    @Published private(set) var dayOneProgress: ChapterDayOneImport.Progress?
    /// Reads the picked export off the main actor; the summary is shown before anything is written.
    func readDayOneArchive(_ url: URL) async throws -> DayOneArchive {
        guard identity != nil else { throw ChapterError.authentication }
        let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        return try await DayOneArchive.parse(data)
    }
    /// Runs the import. Each entry is committed with its media in one encrypted write, so a
    /// failure or lock part-way leaves only whole entries (the web keeps a half-written one).
    func importDayOne(_ archive: DayOneArchive) async throws -> ChapterDayOneImport.Summary {
        guard identity != nil, dayOneProgress == nil else { throw ChapterError.conflict }
        let journals = snapshot.records.filter { $0.kind == "journal" && !$0.deleted }.map { (id: $0.journalID, name: $0.body["name"]?.string ?? "") }
        let target = VaultDayOneTarget(model: self, attempt: generation, journals: journals)
        dayOneProgress = ChapterDayOneImport.Progress(done: 0, total: archive.entryCount, current: "")
        defer { dayOneProgress = nil }
        do {
            return try await ChapterDayOneImport.run(archive, into: target) { p in
                Task { @MainActor in if (self.dayOneProgress?.done ?? Int.max) < p.done { self.dayOneProgress = p } }
            }
        } catch { await target.abandon(); throw error }
    }
    func importNotebook(id: String, name: String, subtitle: String, color: String, cover: String, attempt: UUID) throws {
        guard attempt == generation else { throw CancellationError() }
        try createJournal(name: name, subtitle: subtitle, color: color, cover: cover, journalID: id)
    }
    /// Encrypts one imported file into the upload queue's staging area (not yet published).
    func stageImportMedia(_ data: Data, name: String, mime: String, attempt: UUID) async throws -> MediaUpload {
        guard attempt == generation, let identity, let mediaFiles, mediaImport == nil else { throw CancellationError() }
        let id = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased(), key = identity.mediaKey
        let task = Task.detached(priority: .userInitiated) { () throws -> MediaUpload in
            let root = try EncryptedSnapshotStore.applicationDirectory().appendingPathComponent("ImportStaging", isDirectory: true) // removed on lock
            try EncryptedMediaFiles.protectedDirectory(root)
            let source = root.appendingPathComponent(id)
            try data.write(to: source, options: [.atomic, .completeFileProtection])
            defer { try? FileManager.default.removeItem(at: source) }
            return try mediaFiles.stage(source: source, id: id, name: name, mime: mime, key: key)
        }
        mediaImport = task
        defer { if attempt == generation { mediaImport = nil } }
        let upload = try await task.value
        guard attempt == generation else { try? mediaFiles.discardUnpublished(id: id); throw CancellationError() }
        return upload
    }
    func commitImportedEntry(id: String, journalID: String, title: String?, bodyJSON: String, bodyText: String, labels: [String], createdAt: Double, uploads: [MediaUpload], attempt: UUID) throws {
        guard attempt == generation, identity != nil else { throw CancellationError() }
        let record = try VaultSnapshot.importedEntry(id: id, clock: try nextClock(), journalID: journalID, title: title, bodyJSON: bodyJSON, bodyText: bodyText, labels: labels, createdAt: createdAt)
        var next = snapshot; try next.addImportedEntry(record, uploads: uploads)
        try commit(next); scheduleSync()
    }
    /// Staged files of an entry that was never committed.
    func discardImportUploads(_ uploads: [MediaUpload]) {
        guard let mediaFiles else { return }
        for upload in uploads where !(snapshot.mediaUploads ?? []).contains(where: { $0.id == upload.id }) { try? mediaFiles.discardUnpublished(id: upload.id) }
    }
    /// Web ExportJournalSheet progress (`done` of `total`, and what is being added).
    @Published private(set) var exportProgress: ChapterExport.Progress?
    private static func exportsDirectory() throws -> URL { try EncryptedSnapshotStore.applicationDirectory().appendingPathComponent("Exports", isDirectory: true) }
    /// The plaintext archive must not outlive its sheet or the unlocked session.
    func discardExports() { if let root = try? Self.exportsDirectory() { try? FileManager.default.removeItem(at: root) } }
    /// Web exportJournal for one notebook: the documented `mneme-journal-export` v1 zip,
    /// built on this device. Media comes from the upload queue or the local cache, else the
    /// relay (decrypted here); what can't be fetched is recorded as missing, like the web.
    /// Locking the vault aborts the export and deletes the partial archive.
    func exportJournal(_ journal: VaultRecord) async throws -> (URL, ChapterExport.Summary) {
        guard identity != nil else { throw ChapterError.authentication }
        let attempt = generation
        discardExports()
        let root = try Self.exportsDirectory(); try EncryptedMediaFiles.protectedDirectory(root)
        let folder = root.appendingPathComponent(UUID().uuidString, isDirectory: true); try EncryptedMediaFiles.protectedDirectory(folder)
        let b = journal.body, now = (Date().timeIntervalSince1970 * 1000).rounded(.down)
        let meta = ChapterExport.Journal(id: journal.journalID, name: b["name"]?.string ?? "", subtitle: b["subtitle"]?.string ?? "", color: b["color"]?.string ?? "",
                                         cover: b["cover"]?.string ?? "", createdAt: b["createdAt"]?.number, updatedAt: b["updatedAt"]?.number)
        let file = folder.appendingPathComponent(ChapterExport.filename(name: meta.name, now: now))
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        exportProgress = ChapterExport.Progress(done: 0, total: 0, current: "")
        defer { exportProgress = nil }
        do {
            let summary = try await ChapterExport.writeZip(to: file, journal: meta, entries: ChapterExport.entries(snapshot.records), now: now, generator: ("Chapter", version),
                media: { _, att in try await self.exportMedia(att, attempt: attempt) },
                progress: { p in Task { @MainActor in if (self.exportProgress?.done ?? -1) < p.done { self.exportProgress = p } } })
            guard attempt == generation else { throw CancellationError() }
            return (file, summary)
        } catch { try? FileManager.default.removeItem(at: folder); throw error }
    }
    private func exportMedia(_ att: JSONValue, attempt: UUID) async throws -> Data? {
        guard attempt == generation, identity != nil else { throw CancellationError() }
        guard let media = VaultMedia(att), let url = try? await downloadMedia(media) else {
            guard attempt == generation else { throw CancellationError() }
            return nil
        }
        defer { discardPlayback(url) }
        return try? Data(contentsOf: url)
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

/// The app side of ChapterDayOneImport.run: entries are buffered until their final document
/// arrives, then committed together with their staged media.
final class VaultDayOneTarget: DayOneImportTarget {
    struct Pending { let journalID: String; var uploads: [MediaUpload] = [] }
    let model: VaultModel, attempt: UUID
    let importJournals: [(id: String, name: String)]
    private var pending: [String: Pending] = [:]
    init(model: VaultModel, attempt: UUID, journals: [(id: String, name: String)]) { self.model = model; self.attempt = attempt; importJournals = journals }

    func importNewJournal(id: String, name: String, subtitle: String, color: String, cover: String) async throws {
        try await model.importNotebook(id: id, name: name, subtitle: subtitle, color: color, cover: cover, attempt: attempt)
    }
    func importCreateEntry(journalID: String, title: String?, labels: [String]) async throws -> String {
        let id = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        pending[id] = Pending(journalID: journalID)
        return id
    }
    /// Web addMedia: empty files are refused; the attachment carries the importer's kind, the
    /// Blob type (or the web's per-kind fallback) and createdAt. Files over the native media
    /// limit are skipped like any file that can't be attached.
    func importAddMedia(entryID: String, _ m: DayOneArchive.Resolved) async throws -> JSValue? {
        guard pending[entryID] != nil else { throw ChapterError.conflict }
        guard !m.data.isEmpty, m.data.count <= MediaLimits.maximumPlainBytes else { return nil }
        let fallback = m.kind == .audio ? "audio/webm" : m.kind == .video ? "video/webm" : m.kind == .image ? "image/jpeg" : "application/octet-stream"
        let mime = m.mime.isEmpty ? fallback : m.mime
        let upload = try await model.stageImportMedia(m.data, name: m.name, mime: mime, attempt: attempt)
        pending[entryID]?.uploads.append(upload)
        var o: [(String, JSValue)] = [("id", .string(upload.id)), ("kind", .string(m.kind.rawValue)), ("mime", .string(mime)), ("bytes", .number(Double(m.data.count)))]
        if let d = m.durationMs { o.append(("durationMs", d.isFinite ? .number(d) : .null)) }
        o.append(("name", .string(m.name)))
        if let w = m.width { o.append(("width", w)) }
        if let h = m.height { o.append(("height", h)) }
        o.append(("createdAt", .number((Date().timeIntervalSince1970 * 1000).rounded(.down))))
        return .object(o)
    }
    func importUpdateEntry(id: String, title: String?, bodyJSON: String, bodyText: String, labels: [String], createdAt: Double) async throws {
        guard let p = pending.removeValue(forKey: id) else { throw ChapterError.conflict }
        do {
            try await model.commitImportedEntry(id: id, journalID: p.journalID, title: title, bodyJSON: bodyJSON, bodyText: bodyText, labels: labels,
                                                createdAt: createdAt, uploads: p.uploads, attempt: attempt)
        } catch { await model.discardImportUploads(p.uploads); throw error }
    }
    func abandon() async {
        let uploads = pending.values.flatMap(\.uploads); pending = [:]
        await model.discardImportUploads(uploads)
    }
}

