// SPDX-License-Identifier: AGPL-3.0-or-later
import XCTest
import CryptoKit
@testable import ChapterCore

final class RichDocumentTests: XCTestCase {
    func fixture() throws -> [String: JSONValue] {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "rich-document", withExtension: "json"))
        return try JSONDecoder().decode([String: JSONValue].self, from: Data(contentsOf: url))
    }
    func json(_ value: JSONValue) throws -> String { String(decoding: try JSONEncoder().encode(value), as: UTF8.self) }
    func testActualWebPreviewAndOpaqueRoundTrip() throws {
        let f = try fixture(), doc = try RichDocument(json: json(f["original"]!))
        XCTAssertEqual(doc.root, f["original"]); XCTAssertEqual(doc.plainText, f["originalPreview"]?.string)
        XCTAssertEqual(try RichDocument(json: doc.encoded()).root, doc.root)
        XCTAssertFalse(doc.textLeaves.contains(where: { $0.text == "Opaque future text" }))
    }
    func testSelectedTextAndTaskEditsPreserveEveryOtherField() throws {
        let f = try fixture(); var doc = try RichDocument(json: json(f["original"]!))
        try doc.replaceText(at: [0,0], with: "Edited 📝 heading"); try doc.toggleTask(at: [2,0])
        XCTAssertEqual(doc.root, f["edited"]); XCTAssertEqual(doc.plainText, f["editedPreview"]?.string)
        XCTAssertThrowsError(try doc.replaceText(at: [13,0], with: "Must not interpret future payload"))
        XCTAssertEqual(doc.root, f["edited"])
    }
    func testEmptyRunDeletionPreservesParentAndOtherRuns() throws {
        var doc = try RichDocument(json: #"{"type":"doc","content":[{"type":"paragraph","attrs":{"keep":1},"content":[{"type":"text","text":"a","marks":[{"type":"bold"}]},{"type":"text","text":"b"}]}]}"#)
        try doc.replaceText(at: [0,0], with: "")
        XCTAssertEqual(doc.node.children[0].children.count, 1)
        XCTAssertEqual(doc.node.children[0].children[0].text, "b")
        XCTAssertEqual(doc.node.children[0].value["attrs"]["keep"], .number(1))
        try doc.replaceText(at: [0,0], with: ""); XCTAssertTrue(doc.node.children[0].children.isEmpty)
    }
    func testInvalidPathsMalformedTreesAndStaleRecordsFailClosed() throws {
        var doc = try RichDocument(json: #"{"type":"doc","content":[{"type":"paragraph"}]}"#)
        let original = doc.root
        for path in [[], [-1], [99], [0], [0,0], [Int.max]] { XCTAssertThrowsError(try doc.replaceText(at: path, with: "x")) }
        XCTAssertEqual(doc.root, original); XCTAssertThrowsError(try doc.toggleTask(at: [0]))
        for value in [#"{"type":"doc","content":7}"#, #"{"type":"doc","content":[{"type":"text","text":1}]}"#, #"{"type":"paragraph"}"#] { XCTAssertThrowsError(try RichDocument(json: value)) }
        let raw = try doc.encoded(), record = VaultRecord(id: "x", clock: 1, body: ["bodyJson": .string(raw)])
        XCTAssertThrowsError(try record.editingRichDocument(expected: raw + " ") { _ in })
        var metadata = record; metadata.body["kind"] = .string("journal")
        XCTAssertThrowsError(try metadata.editingRichDocument(expected: raw) { _ in })
        var deleted = record; deleted.deleted = true
        XCTAssertThrowsError(try deleted.editingRichDocument(expected: raw) { _ in })
    }
    func testUnicodeRunReplacementAndClockFailureDoNotMutateSource() throws {
        let raw = #"{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":"👩🏽‍💻 é","marks":[{"type":"bold"}]}]}]}"#
        let record = VaultRecord(id: "unicode", clock: Int64.max, body: ["bodyJson": .string(raw)])
        XCTAssertThrowsError(try record.editingRichDocument(expected: raw) { try $0.replaceText(at: [0,0], with: "New 🧑‍🚀") })
        XCTAssertEqual(record.body["bodyJson"]?.string, raw)
        var doc = try RichDocument(json: raw); try doc.replaceText(at: [0,0], with: "New 🧑‍🚀")
        XCTAssertEqual(doc.node.children[0].children[0].value["marks"].array.first?["type"].string, "bold")
    }
    func testNativeRichEditCiphertextOpensInActualWeb() throws {
        let f = try fixture(), raw = try json(f["original"]!)
        let record = VaultRecord(id: "fedcba9876543210fedcba9876543210", clock: 1, body: ["bodyJson": .string(raw), "unknownFuture": .object(["preserve": .bool(true)])])
        let edited = try record.editingRichDocument(expected: raw) { doc in
            try doc.replaceText(at: [0,0], with: "Edited 📝 heading"); try doc.toggleTask(at: [2,0])
        }
        XCTAssertTrue(edited.dirty); XCTAssertGreaterThan(edited.clock, record.clock)
        if let path = ProcessInfo.processInfo.environment["CHAPTER_NATIVE_OUTPUT"] {
            let url = try XCTUnwrap(Bundle.module.url(forResource: "web-v1", withExtension: "json"))
            let base = try JSONDecoder().decode(ChapterCoreTests.Fixture.self, from: Data(contentsOf: url))
            let identity = try VaultIdentity(seed: RecoveryPhrase.seed(base.phrase))
            let cipher = try VaultCipher.sealRecord(JSONEncoder().encode(edited.body), key: identity.dataKey, id: edited.id)
            try JSONEncoder().encode(["id":edited.id, "record":cipher.base64EncodedString()]).write(to: URL(fileURLWithPath: path + ".rich"))
        }
    }
    func testOldLocalSnapshotMigratesWithoutRekeyAndDraftsSurviveEncryption() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let key = SymmetricKey(size: .bits256), disk = EncryptedSnapshotStore(directory: dir, namespace: "rich-test", key: key)
        var old = try JSONDecoder().decode(VaultSnapshot.self, from: Data(#"{"version":1,"records":[],"cursor":9,"conflicts":[]}"#.utf8))
        XCTAssertNil(old.richDrafts); try disk.save(old)
        let originalBytes = try Data(contentsOf: dir.appendingPathComponent("rich-test.vault"))
        var migrated = try disk.load(); XCTAssertEqual(migrated.version, 3); XCTAssertEqual(migrated.cursor, 9)
        XCTAssertEqual(try Data(contentsOf: dir.appendingPathComponent("rich-test.vault")), originalBytes, "Loading must not overwrite the old snapshot")
        let draft = RichDraft(entryID: "entry", path: [0,0], expectedDocument: "original", text: "PRIVATE UNSENT DRAFT")
        migrated.richDrafts = [draft]; try disk.save(migrated)
        XCTAssertEqual(try disk.load().richDrafts, [draft])
        XCTAssertNil(try Data(contentsOf: dir.appendingPathComponent("rich-test.vault")).range(of: Data(draft.text.utf8)))
        old.version = 99; try disk.save(old); XCTAssertThrowsError(try disk.load())
    }

    func testActualWebUnicodeWhitespacePreviewCases() throws {
        let f = try fixture()
        for item in f["previewCases"]?.array ?? [] {
            XCTAssertEqual(try RichDocument(json: json(item["doc"])).plainText, item["text"].string)
        }
    }

}
