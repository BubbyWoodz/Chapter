// SPDX-License-Identifier: AGPL-3.0-or-later
import XCTest
import CryptoKit
@testable import ChapterCore

final class ChapterCoreTests: XCTestCase {
    struct Fixture: Decodable {
        let phrase, seed, dataKey, mediaKey, ownerId, ownerPublic, ownerSigningPublic, devicePublic: String
        let signature, ownerSignature, recordId, body, record, legacy, media: String
    }
    func fixture() throws -> Fixture {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "web-v1", withExtension: "json"))
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }
    func testBIP39KeysAndOwnerAuthorizedRegistrationMatchWeb() throws {
        let f = try fixture(); let seed = try RecoveryPhrase.seed(f.phrase)
        let id = try VaultIdentity(seed: seed)
        XCTAssertEqual(seed.hex, f.seed); XCTAssertEqual(id.dataKey.hex, f.dataKey); XCTAssertEqual(id.mediaKey.hex, f.mediaKey)
        XCTAssertEqual(id.ownerID, f.ownerId); XCTAssertEqual(id.ownerPublic.hex, f.ownerPublic)
        XCTAssertEqual(id.ownerSigning.publicKey.rawRepresentation.hex, f.ownerSigningPublic)
        XCTAssertEqual(id.deviceSigning.publicKey.rawRepresentation.hex, f.devicePublic)
        let register = try id.registration()
        XCTAssertEqual(register["signature"], f.signature); XCTAssertEqual(register["owner_signature"], f.ownerSignature)
    }
    func testPhraseNormalizationAndInvalidChecksum() throws {
        let f = try fixture()
        XCTAssertEqual(try RecoveryPhrase.seed("  " + f.phrase.uppercased().replacingOccurrences(of: " ", with: "\n") + " "), try RecoveryPhrase.seed(f.phrase))
        XCTAssertThrowsError(try RecoveryPhrase.seed("legal winner thank year wave sausage worth useful legal winner thank legal"))
        XCTAssertThrowsError(try RecoveryPhrase.seed("not a recovery phrase"))
        XCTAssertThrowsError(try VaultIdentity(seed: Data(count: 32)))
    }
    func testWebToSwiftAEADRecordLegacyAndMedia() throws {
        let f = try fixture(); let id = try VaultIdentity(seed: RecoveryPhrase.seed(f.phrase))
        for encoded in [f.record, f.legacy] {
            let opened = try VaultCipher.openRecord(XCTUnwrap(Data(base64Encoded: encoded)), key: id.dataKey, id: f.recordId)
            XCTAssertEqual(String(decoding: opened, as: UTF8.self), f.body)
        }
        let media = try VaultCipher.openMediaChunk(XCTUnwrap(Data(base64Encoded: f.media)), key: id.mediaKey, id: f.recordId, index: 0, total: 1)
        XCTAssertEqual(String(decoding: media, as: UTF8.self), "Public media bytes")
    }
    func testTamperWrongIDKeyAndChunkPositionFailClosed() throws {
        let f = try fixture(); let id = try VaultIdentity(seed: RecoveryPhrase.seed(f.phrase))
        let cipher = try XCTUnwrap(Data(base64Encoded: f.record))
        XCTAssertThrowsError(try VaultCipher.openRecord(cipher, key: id.dataKey, id: "different-id"))
        XCTAssertThrowsError(try VaultCipher.openRecord(cipher, key: id.mediaKey, id: f.recordId))
        var tampered = cipher; tampered[tampered.count - 1] ^= 1
        XCTAssertThrowsError(try VaultCipher.openRecord(tampered, key: id.dataKey, id: f.recordId))
        var unknown = cipher; unknown[0] = 2
        XCTAssertThrowsError(try VaultCipher.openRecord(unknown, key: id.dataKey, id: f.recordId))
        XCTAssertThrowsError(try VaultCipher.openRecord(Data([1]), key: id.dataKey, id: f.recordId))
        XCTAssertThrowsError(try VaultCipher.openMediaChunk(XCTUnwrap(Data(base64Encoded: f.media)), key: id.mediaKey, id: f.recordId, index: 0, total: 2))
    }
    func testSwiftToWebFixtureOutput() throws {
        let f = try fixture(); let id = try VaultIdentity(seed: RecoveryPhrase.seed(f.phrase))
        let record = try VaultCipher.sealRecord(Data(f.body.utf8), key: id.dataKey, id: f.recordId)
        let media = try VaultCipher.seal(Data("Public media bytes".utf8), key: id.mediaKey, aad: Data("media:\(f.recordId):0/1".utf8))
        XCTAssertEqual(try VaultCipher.openRecord(record, key: id.dataKey, id: f.recordId), Data(f.body.utf8))
        XCTAssertNotEqual(record, try VaultCipher.sealRecord(Data(f.body.utf8), key: id.dataKey, id: f.recordId))
        if let path = ProcessInfo.processInfo.environment["CHAPTER_NATIVE_OUTPUT"] {
            try JSONEncoder().encode(["record": record.base64EncodedString(), "media": media.base64EncodedString()]).write(to: URL(fileURLWithPath: path))
        }
    }
    func testServerAddressDoesNotSmuggleCredentialsOrLosePrefix() throws {
        for bad in ["http://server.local", "https://name:secret@server.local", "https://server.local?q=secret", "https://server.local/#fragment", "/relative", "file:///tmp/foo"] {
            XCTAssertThrowsError(try ServerAddress(bad), bad)
        }
        let address = try ServerAddress(" https://chapter.tailnet.ts.net:8443/mneme/ ")
        XCTAssertEqual(address.endpoint("v1/register").absoluteString, "https://chapter.tailnet.ts.net:8443/mneme/v1/register")
        XCTAssertEqual(try ServerAddress("https://[fd7a:115c:a1e0::1]/chapter/").endpoint("v1/sync/pull").path, "/chapter/v1/sync/pull")
    }
    func testSnapshotAtomicEncryptedRoundTripAndFailedOpenDoesNotOverwrite() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let key = SymmetricKey(size: .bits256)
        let disk = EncryptedSnapshotStore(directory: dir, namespace: "test", key: key)
        XCTAssertEqual(try disk.load(), VaultSnapshot())
        var value = VaultSnapshot(); value.cursor = 123
        value.records = [VaultRecord(id: "id", clock: 10, body: ["title": .string("PRIVATE TITLE"), "unknownFuture": .object(["deep": .bool(true)])], dirty: true)]
        try disk.save(value)
        XCTAssertEqual(try disk.load(), value)
        let url = dir.appendingPathComponent("test.vault"), bytes = try Data(contentsOf: url)
        XCTAssertNil(String(data: bytes, encoding: .utf8)?.range(of: "PRIVATE TITLE"))
        XCTAssertFalse(bytes.range(of: Data("PRIVATE TITLE".utf8)) != nil)
        let wrong = EncryptedSnapshotStore(directory: dir, namespace: "test", key: SymmetricKey(size: .bits256))
        XCTAssertThrowsError(try wrong.load()); XCTAssertEqual(try Data(contentsOf: url), bytes)
        var tampered = bytes; tampered[0] ^= 1; try tampered.write(to: url)
        XCTAssertThrowsError(try disk.load()); XCTAssertEqual(try Data(contentsOf: url), tampered)
    }
    func testStorageNamespaceSeparatesServersAndVaults() {
        let a = EncryptedSnapshotStore.namespace(server: URL(string: "https://a/mneme")!, owner: "owner")
        XCTAssertNotEqual(a, EncryptedSnapshotStore.namespace(server: URL(string: "https://b/mneme")!, owner: "owner"))
        XCTAssertNotEqual(a, EncryptedSnapshotStore.namespace(server: URL(string: "https://a/mneme")!, owner: "different"))
    }
    func testRemoteMergePreservesLosingDirtyVersionAndUnknownFields() {
        var snapshot = VaultSnapshot()
        let local = VaultRecord(id: "x", clock: 10, body: ["title": .string("unsynced")], dirty: true)
        snapshot.records = [local]
        let remote = VaultRecord(id: "x", clock: 11, body: ["title": .string("remote"), "future": .array([.bool(true)])])
        snapshot.merge(remote); XCTAssertEqual(snapshot.records, [remote]); XCTAssertEqual(snapshot.conflicts, [local])
        snapshot.merge(local); XCTAssertEqual(snapshot.records, [remote])
        snapshot.merge(remote); XCTAssertEqual(snapshot.conflicts.count, 1)
    }
    func testPlainEditorNeverFlattensAnotherClientRichDocument() throws {
        var native = VaultRecord(id: "x", clock: 1, body: ["chapterNativePlain": .bool(true), "bodyText": .string("Hello"), "bodyJson": .string(try VaultRecord.plainDocument("Hello"))])
        XCTAssertTrue(native.editablePlainText)
        native.body["bodyJson"] = .string("{\"type\":\"doc\",\"content\":[{\"type\":\"videoInterview\",\"attrs\":{\"cards\":[]}}]}")
        XCTAssertFalse(native.editablePlainText)
        native.body.removeValue(forKey: "chapterNativePlain")
        XCTAssertFalse(native.editablePlainText)
    }
    func testAcknowledgementCannotClearNewerOfflineEdit() {
        let sent = VaultRecord(id: "x", clock: 10, body: [:], dirty: true)
        let newer = VaultRecord(id: "x", clock: 11, body: [:], dirty: true)
        var snapshot = VaultSnapshot(); snapshot.records = [newer]
        snapshot.acknowledge(sent); XCTAssertTrue(snapshot.records[0].dirty)
        snapshot.acknowledge(newer); XCTAssertFalse(snapshot.records[0].dirty)
    }
    func testMediaWalkIncludesAllWebCustomNodeTypesAndDeduplicates() throws {
        func media(_ id: String) -> JSONValue { .object(["id": .string(id), "mime": .string("image/png"), "bytes": .number(10)]) }
        func node(_ type: String, _ attrs: [String: JSONValue]) -> JSONValue { .object(["type": .string(type), "attrs": .object(attrs)]) }
        let doc: JSONValue = .object(["type": .string("doc"), "content": .array([
            node("mediaAttachment", ["id": .string("single"), "kind": .string("image")]),
            node("mediaGallery", ["images": .array([media("gallery")])]),
            node("locationMap", ["map": media("map"), "photo": media("photo")]),
            node("videoInterview", ["cards": .array([.object(["clip": media("clip")])]), "film": media("film")])
        ])])
        let body: [String: JSONValue] = ["bodyJson": .string(String(decoding: try JSONEncoder().encode(doc), as: UTF8.self)), "attachments": .array([media("single"), media("legacy")])]
        let record = VaultRecord(id: "entry", clock: 1, body: body)
        XCTAssertEqual(Set(record.mediaReferences.map(\.id)), Set(["single", "gallery", "map", "photo", "clip", "film", "legacy"]))
        XCTAssertEqual(record.mediaReferences.count, 7)
    }

    func testCheckedClockRejectsOverflowAndNonJavaScriptIntegers() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertEqual(try ProtocolNumbers.nextClock(after: 0, now: now), 1_700_000_000_000)
        XCTAssertEqual(try ProtocolNumbers.nextClock(after: 1_700_000_000_010, now: now), 1_700_000_000_011)
        XCTAssertEqual(try ProtocolNumbers.nextClock(after: ProtocolNumbers.maxWireInteger - 1, now: now), ProtocolNumbers.maxWireInteger)
        for invalid in [Int64.min, -1, ProtocolNumbers.maxWireInteger, Int64.max] {
            XCTAssertThrowsError(try ProtocolNumbers.nextClock(after: invalid, now: now))
        }
        for seconds in [Double.nan, .infinity, -.infinity, Double.greatestFiniteMagnitude, Double(Int64.max), -1] {
            XCTAssertThrowsError(try ProtocolNumbers.nextClock(after: 0, now: Date(timeIntervalSince1970: seconds)))
        }
    }
    func testMalformedWireNumbersAndStalledCursorFailClosed() throws {
        let valid = #"{"entries":[],"cursor":0,"more":false}"#
        XCTAssertNoThrow(try JSONDecoder().decode(PullPage.self, from: Data(valid.utf8)).validate(since: 0))
        for json in [
            #"{"entries":[],"cursor":9223372036854775807,"more":false}"#,
            #"{"entries":[],"cursor":9223372036854775808,"more":false}"#,
            #"{"entries":[],"cursor":-1,"more":false}"#,
            #"{"entries":[],"cursor":1,"more":false}"#,
            #"{"entries":[],"cursor":0,"more":true}"#,
            #"{"entries":[{"entry_id":"x","lww_clock":9223372036854775807,"ciphertext":"","deleted":false}],"cursor":1,"more":false}"#,
            #"{"entries":[{"entry_id":"x","lww_clock":1.5,"ciphertext":"","deleted":false}],"cursor":1,"more":false}"#,
            #"{"entries":[{"entry_id":"x","lww_clock":1,"ciphertext":"","deleted":false}],"cursor":0,"more":false}"#
        ] {
            XCTAssertThrowsError(try JSONDecoder().decode(PullPage.self, from: Data(json.utf8)).validate(since: 0), json)
        }
    }
    func testUntrustedDatesAndMediaSizesNeverTrapOrTruncate() {
        let epoch = Date(timeIntervalSince1970: 0)
        for invalid in [Double.nan, .infinity, -.infinity, Double.greatestFiniteMagnitude, Double(Int64.max)] {
            XCTAssertEqual(ProtocolNumbers.displayDate(milliseconds: invalid), epoch)
            XCTAssertNil(VaultMedia(.object(["id": .string("x"), "bytes": .number(invalid)])))
        }
        XCTAssertEqual(ProtocolNumbers.displayDate(milliseconds: 1_700_000_000_000), Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertNil(VaultMedia(.object(["id": .string("x"), "bytes": .number(-1)])))
        XCTAssertNil(VaultMedia(.object(["id": .string("x"), "bytes": .number(1.5)])))
        XCTAssertEqual(VaultMedia(.object(["id": .string("x"), "bytes": .number(10)]))?.bytes, 10)
    }
    func testLostAcknowledgementAndTombstoneConflictsRetainIntent() {
        let original = VaultRecord(id: "x", clock: 10, body: ["title": .string("same")], dirty: true)
        var snapshot = VaultSnapshot(); snapshot.records = [original]
        var received = original; received.dirty = false
        snapshot.merge(received); XCTAssertFalse(snapshot.records[0].dirty)
        var deleted = original; deleted.deleted = true
        snapshot.records = [deleted]; received.clock = 11
        snapshot.merge(received); XCTAssertEqual(snapshot.conflicts, [deleted])
        snapshot = VaultSnapshot(); snapshot.records = [original]
        received.clock = 10; received.body["title"] = .string("collision")
        snapshot.merge(received); XCTAssertEqual(snapshot.records, [original]); XCTAssertEqual(snapshot.conflicts, [received])
        snapshot.acknowledge(received); XCTAssertTrue(snapshot.records[0].dirty)
    }

}
