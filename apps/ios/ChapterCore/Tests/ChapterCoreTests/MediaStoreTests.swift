// SPDX-License-Identifier: AGPL-3.0-or-later
import XCTest
import CryptoKit
@testable import ChapterCore

final class MediaStoreTests: XCTestCase {
    func directory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true); return dir
    }
    func testChunkBoundariesCipherTotalsAndActualWebDecoderOutput() throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let files = try EncryptedMediaFiles(directory: dir, namespace: "public-test")
        let fixtureURL = try XCTUnwrap(Bundle.module.url(forResource: "web-v1", withExtension: "json"))
        let fixture = try JSONDecoder().decode(ChapterCoreTests.Fixture.self, from: Data(contentsOf: fixtureURL))
        let identity = try VaultIdentity(seed: RecoveryPhrase.seed(fixture.phrase))
        for size in [0, 1, MediaLimits.chunkBytes, 2 * MediaLimits.chunkBytes + 17] {
            let plain = Data((0..<size).map { UInt8(($0 * 31 + 7) % 256) })
            let source = dir.appendingPathComponent("selected"); try plain.write(to: source)
            let id = UUID().uuidString.replacingOccurrences(of: "-", with: "")
            let upload = try files.stage(source: source, id: id, name: "PRIVATE-FILENAME", mime: "application/octet-stream", key: identity.mediaKey)
            try upload.validate()
            XCTAssertEqual(upload.cipherBytes, Int64(size + upload.chunks * 41))
            var reopened = Data(), chunks: [String] = []
            let restart = try EncryptedMediaFiles(directory: dir, namespace: "public-test")
            for index in 0..<upload.chunks {
                let cipher = try restart.read(id: id, index: index); chunks.append(cipher.base64EncodedString())
                reopened.append(try VaultCipher.openMediaChunk(cipher, key: identity.mediaKey, id: id, index: index, total: upload.chunks))
                XCTAssertThrowsError(try VaultCipher.openMediaChunk(cipher, key: identity.mediaKey, id: id + "x", index: index, total: upload.chunks))
                if size > 1 { XCTAssertNotEqual(cipher, plain) }
            }
            XCTAssertEqual(reopened, plain)
            if size > MediaLimits.chunkBytes, let path = ProcessInfo.processInfo.environment["CHAPTER_NATIVE_OUTPUT"] {
                let body = try JSONDecoder().decode([String: JSONValue].self, from: Data(fixture.body.utf8))
                let raw = try XCTUnwrap(body["bodyJson"]?.string)
                var snapshot = VaultSnapshot(); snapshot.records = [VaultRecord(id: fixture.recordId, clock: 1, body: body)]
                try snapshot.attach(upload, entryID: fixture.recordId, expectedDocument: raw)
                let recordCipher = try VaultCipher.sealRecord(JSONEncoder().encode(snapshot.records[0].body), key: identity.dataKey, id: fixture.recordId)
                var output: [String: JSONValue] = ["id": .string(id), "chunks": .array(chunks.map(JSONValue.string)), "plainBytes": .number(Double(size)), "cipherBytes": .number(Double(upload.cipherBytes))]
                output["recordId"] = .string(fixture.recordId); output["record"] = .string(recordCipher.base64EncodedString())
                try JSONEncoder().encode(output).write(to: URL(fileURLWithPath: path + ".media-upload"))
            }
        }
    }
    func testOutboxAndBodyAtomicSnapshotRestartStaleDraftAndDowngradeGuard() throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let key = SymmetricKey(size: .bits256), disk = EncryptedSnapshotStore(directory: dir, namespace: "queue", key: key)
        let files = try EncryptedMediaFiles(directory: dir, namespace: "queue"), source = dir.appendingPathComponent("selected")
        try Data("PRIVATE ATTACHMENT".utf8).write(to: source)
        let upload = try files.stage(source: source, id: "0123456789abcdef", name: "PRIVATE-FILENAME", mime: "text/plain", key: Data(repeating: 4, count: 32))
        let raw = #"{"type":"doc","future":{"keep":true},"content":[{"type":"futureNode","attrs":{"x":1}}]}"#
        var old = VaultSnapshot(); old.version = 2; old.cursor = 9
        old.records = [VaultRecord(id: "entry", clock: 1, body: ["bodyJson": .string(raw), "privateMetadata": .bool(true)], dirty: true)]
        let draft = RichDraft(entryID: "entry", path: [0], expectedDocument: raw, text: "PRIVATE DRAFT"); old.richDrafts = [draft]
        try disk.save(old); let oldBytes = try Data(contentsOf: dir.appendingPathComponent("queue.vault"))
        var next = try disk.load(); XCTAssertEqual(next.version, 3); XCTAssertEqual(next.cursor, 9)
        XCTAssertEqual(try Data(contentsOf: dir.appendingPathComponent("queue.vault")), oldBytes)
        XCTAssertThrowsError(try next.attach(upload, entryID: "entry", expectedDocument: "stale")); XCTAssertEqual(next.records, old.records); XCTAssertNil(next.mediaUploads)
        try next.attach(upload, entryID: "entry", expectedDocument: raw); try disk.save(next)
        let restart = try disk.load(); XCTAssertEqual(restart.mediaUploads, [upload]); XCTAssertEqual(restart.richDrafts, [draft]); XCTAssertTrue(restart.uploadableRecords.isEmpty)
        XCTAssertEqual(restart.records[0].mediaReferences.map(\.id), [upload.id])
        let document = try RichDocument(json: XCTUnwrap(restart.records[0].body["bodyJson"]?.string))
        XCTAssertEqual(document.root["future"]["keep"], .bool(true)); XCTAssertEqual(document.node.children[0].type, "futureNode")
        XCTAssertThrowsError(try restart.records[0].editingRichDocument(expected: draft.expectedDocument) { try $0.replaceText(at: draft.path, with: draft.text) })
        XCTAssertNil(try Data(contentsOf: dir.appendingPathComponent("queue.vault")).range(of: Data(upload.name.utf8)))
        // Exact version guard in shipped v1/v2 preview readers: new local format
        // is refused, not decoded/re-saved with an unknown outbox silently lost.
        XCTAssertFalse(restart.version == 1 || restart.version == 2)
        var independent = restart
        independent.records.append(VaultRecord(id: "unrelated", clock: 1, body: ["bodyJson": .string("{\"type\":\"doc\",\"content\":[]}")], dirty: true))
        XCTAssertEqual(independent.uploadableRecords.map(\.id), ["unrelated"], "A failed media upload must not gate unrelated entries")
        independent.acknowledge(old.records[0])
        XCTAssertTrue(independent.records[0].dirty, "An in-flight pre-attachment acknowledgment cannot clear the new media-bearing entry")
        XCTAssertEqual(independent.mediaUploads, [upload])
        next = restart; next.mediaUploaded(upload); try disk.save(next)
        XCTAssertEqual(try disk.load().uploadableRecords.count, 1); XCTAssertEqual(try disk.load().mediaUploads, [])
        XCTAssertEqual(try files.read(id: upload.id, index: 0).count, upload.plainBytes + 41)
    }
    func testInvalidPathsOversizeCollisionTamperAndInterruptedStageFailClosed() async throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let files = try EncryptedMediaFiles(directory: dir, namespace: "queue"), source = dir.appendingPathComponent("source")
        try Data("Original bytes".utf8).write(to: source)
        let key = Data(repeating: 9, count: 32), id = "0123456789abcdef"
        let first = try files.stage(source: source, id: id, name: "original", mime: "text/plain", key: key), original = try files.read(id: id, index: 0)
        XCTAssertThrowsError(try files.stage(source: source, id: id, name: "replacement", mime: "text/plain", key: key))
        XCTAssertEqual(try files.read(id: id, index: 0), original)
        for invalid in ["../escape", id + "\n", String(repeating: "a", count: 65), "short", id + "/other", id + "é"] { XCTAssertFalse(MediaLimits.validID(invalid)); XCTAssertThrowsError(try files.read(id: invalid, index: 0)) }
        var altered = original; altered[altered.count - 1] ^= 1
        XCTAssertThrowsError(try VaultCipher.openMediaChunk(altered, key: key, id: id, index: 0, total: first.chunks))
        let handle = try FileHandle(forWritingTo: source); try handle.truncate(atOffset: UInt64(MediaLimits.maximumPlainBytes + 1)); try handle.close()
        XCTAssertThrowsError(try files.stage(source: source, id: "0123456789abcdef99", name: "huge", mime: "x", key: key))
        try Data(repeating: 1, count: 100).write(to: source)
        let task = Task { withUnsafeCurrentTask { $0?.cancel() }; return try files.stage(source: source, id: "0123456789abcdef88", name: "cancelled", mime: "x", key: key) }; task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled import completed") } catch {}
        XCTAssertThrowsError(try files.read(id: "0123456789abcdef88", index: 0))
        XCTAssertEqual(try files.read(id: id, index: 0), original)
    }
}
