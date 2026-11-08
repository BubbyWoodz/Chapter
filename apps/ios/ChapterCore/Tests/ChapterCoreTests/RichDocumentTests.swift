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
        for path in [[], [-1], [99], [0,0], [Int.max]] { XCTAssertThrowsError(try doc.replaceText(at: path, with: "x")) }
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
        var migrated = try disk.load(); XCTAssertEqual(migrated.version, 4); XCTAssertEqual(migrated.cursor, 9)
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

    func testNineAuthoredBlocksFormattingAndOriginalWebCiphertext() throws {
        let f = try fixture(), raw = try json(f["original"]!)
        var record = VaultRecord(id: "native-authoring-record", clock: 1, body: ["bodyJson": .string(raw), "unknownFuture": .object(["preserve": .bool(true)])])
        let draft = try RichDraft(entryID: record.id, path: [0,0], expectedDocument: raw, text: "Public heading").togglingMark("italic")
        record = try draft.applying(to: record)
        for style in RichBlockStyle.allCases {
            let expected = try XCTUnwrap(record.body["bodyJson"]?.string)
            record = try record.editingRichDocument(expected: expected) { try $0.appendTextBlock(text: "Native " + style.rawValue, style: style) }
        }
        let document = try RichDocument(json: XCTUnwrap(record.body["bodyJson"]?.string))
        XCTAssertEqual(document.root, f["authored"]); XCTAssertEqual(document.plainText, f["authoredPreview"]?.string)
        XCTAssertEqual(record.body["unknownFuture"], .object(["preserve": .bool(true)]))
        if let path = ProcessInfo.processInfo.environment["CHAPTER_NATIVE_OUTPUT"] {
            let baseURL = try XCTUnwrap(Bundle.module.url(forResource: "web-v1", withExtension: "json"))
            let base = try JSONDecoder().decode(ChapterCoreTests.Fixture.self, from: Data(contentsOf: baseURL))
            let identity = try VaultIdentity(seed: RecoveryPhrase.seed(base.phrase))
            let cipher = try VaultCipher.sealRecord(JSONEncoder().encode(record.body), key: identity.dataKey, id: record.id)
            try JSONEncoder().encode(["id":record.id,"record":cipher.base64EncodedString()]).write(to: URL(fileURLWithPath: path + ".rich-authoring"))
        }
    }
    func testFormattingRetainsOpaqueMarksAndCodeFollowsOriginalSchema() throws {
        let raw = #"{"type":"doc","content":[{"type":"paragraph","future":7,"content":[{"type":"text","text":"Original","marks":[{"type":"futureMark","attrs":{"keep":true}},{"type":"bold","attrs":{"future":7}}]}]}]}"#
        let record = VaultRecord(id: "marks", clock: 1, body: ["bodyJson": .string(raw)])
        let draft = RichDraft(entryID: "marks", path: [0,0], expectedDocument: raw, text: "Changed")
        let italic = try draft.togglingMark("italic")
        let edited = try italic.applying(to: record)
        let doc = try RichDocument(json: XCTUnwrap(edited.body["bodyJson"]?.string))
        XCTAssertEqual(doc.node.children[0].children[0].value["marks"].array[0], .object(["type": .string("futureMark"), "attrs": .object(["keep": .bool(true)])]))
        XCTAssertEqual(try draft.togglingMark("bold").togglingMark("bold").marks?.last?["attrs"]["future"], .number(7))
        XCTAssertThrowsError(try draft.togglingMark("code")); XCTAssertThrowsError(try draft.togglingMark("link"))
        var droppingOpaque = draft; droppingOpaque.marks = []
        XCTAssertThrowsError(try droppingOpaque.applying(to: record))
        let codeRaw = #"{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":"Plain","marks":[{"type":"bold"}]}]}]}"#
        let codeDraft = try RichDraft(entryID: "code", path: [0,0], expectedDocument: codeRaw, text: "Code").togglingMark("code")
        XCTAssertEqual(codeDraft.marks, [.object(["type": .string("code")])])
        XCTAssertEqual(try codeDraft.togglingMark("italic").marks, [.object(["type": .string("italic")])])
        let blockRaw = #"{"type":"doc","content":[{"type":"codeBlock","content":[{"type":"text","text":"let x = 1"}]}]}"#
        let blockDraft = RichDraft(entryID: "code-block", path: [0,0], expectedDocument: blockRaw, text: "let x = 2")
        XCTAssertFalse(blockDraft.supportsFormatting); XCTAssertThrowsError(try blockDraft.togglingMark("bold"))
    }
    func testEmptyBlockCanBeReeditedAndStaleBlockDraftCannotOverwrite() throws {
        let raw = #"{"type":"doc","future":1,"content":[{"type":"paragraph","attrs":{"future":2},"content":[]}]}"#
        var doc = try RichDocument(json: raw)
        XCTAssertEqual(doc.editableTextNodes.map(\.path), [[0]])
        try doc.replaceText(at: [0], with: "Reopened", marks: [.object(["type": .string("bold")])])
        XCTAssertEqual(doc.node.children[0].value["attrs"]["future"], .number(2))
        XCTAssertEqual(doc.node.children[0].children[0].text, "Reopened")
        let record = VaultRecord(id: "append", clock: 1, body: ["bodyJson": .string(raw)])
        var draft = RichDraft.newBlock(entryID: record.id, expectedDocument: raw); draft.text = "A task"; draft.newBlockStyle = .taskList
        let next = try draft.applying(to: record)
        XCTAssertEqual(try RichDocument(json: XCTUnwrap(next.body["bodyJson"]?.string)).node.children.last?.type, "taskList")
        XCTAssertThrowsError(try draft.applying(to: next), "Stale append must not duplicate or overwrite content")
        XCTAssertThrowsError(try doc.appendTextBlock(text: "", style: .paragraph))
    }
    func testVersion3FormattingMigrationIsAtomicAndOldPreviewRejectsVersion4() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let disk = EncryptedSnapshotStore(directory: dir, namespace: "authoring", key: SymmetricKey(size: .bits256))
        let file = dir.appendingPathComponent("authoring.vault")
        let raw = #"{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":"old"}]}]}"#
        var old = VaultSnapshot(); old.version = 3; old.richDrafts = [RichDraft(entryID: "entry", path: [0,0], expectedDocument: raw, text: "PRIVATE FORMAT DRAFT")]
        try disk.save(old); let bytes = try Data(contentsOf: file)
        var migrated = try disk.load(); XCTAssertEqual(migrated.version, 4); XCTAssertEqual(try Data(contentsOf: file), bytes)
        migrated.richDrafts = [try XCTUnwrap(migrated.richDrafts?.first).togglingMark("bold")]
        var newBlock = RichDraft.newBlock(entryID: "second", expectedDocument: raw); newBlock.text = "PRIVATE BLOCK DRAFT"; newBlock.newBlockStyle = .heading2
        migrated.richDrafts?.append(newBlock)
        var unsafeOldFormat = migrated; unsafeOldFormat.version = 3
        XCTAssertThrowsError(try disk.save(unsafeOldFormat)); XCTAssertEqual(try Data(contentsOf: file), bytes)
        try disk.save(migrated)
        XCTAssertEqual(try disk.load().richDrafts, migrated.richDrafts)
        XCTAssertFalse((1...3).contains(migrated.version), "Exact previous reader guard rejects new local format; no actual old binary/device test claimed")
        let ciphertext = try Data(contentsOf: file)
        XCTAssertNil(ciphertext.range(of: Data("PRIVATE FORMAT DRAFT".utf8))); XCTAssertNil(ciphertext.range(of: Data("PRIVATE BLOCK DRAFT".utf8)))
    }

}
