// SPDX-License-Identifier: AGPL-3.0-or-later
import XCTest
@testable import ChapterCore

final class NotebookTests: XCTestCase {
    private func notebook() -> VaultRecord {
        VaultRecord(id: "public-notebook-record", clock: 12, body: ["kind": .string("journal"), "journalId": .string("public-logical-notebook"), "name": .string("Original"), "subtitle": .string("Original subtitle"), "color": .string("#4E8B85"), "cover": .string("lines"), "createdAt": .number(1), "opaqueFuture": .object(["keep": .array([.bool(true), .number(7)])])])
    }
    func testPatchPreservesIdentityOpaqueDataAndCreationDate() throws {
        let original = notebook()
        let edited = try original.editingJournal(expected: original, name: "  Renamed 📝  ", subtitle: "New subtitle", color: "#B0563A", cover: "grid", now: Date(timeIntervalSince1970: 100))
        XCTAssertEqual(edited.id, original.id); XCTAssertEqual(edited.journalID, original.journalID)
        XCTAssertEqual(edited.body["opaqueFuture"], original.body["opaqueFuture"])
        XCTAssertEqual(edited.body["createdAt"], original.body["createdAt"])
        XCTAssertEqual(edited.title, "Renamed 📝"); XCTAssertEqual(edited.body["cover"], .string("grid"))
        XCTAssertEqual(edited.clock, 100000); XCTAssertTrue(edited.dirty)
        XCTAssertEqual(edited.body["updatedAt"], .number(100000))
        if let path = ProcessInfo.processInfo.environment["CHAPTER_NATIVE_OUTPUT"] {
            let identity = try VaultIdentity(seed: RecoveryPhrase.seed("legal winner thank year wave sausage worth useful legal winner thank yellow"))
            let cipher = try VaultCipher.sealRecord(JSONEncoder().encode(edited.body), key: identity.dataKey, id: edited.id)
            let output: [String: JSONValue] = ["id": .string(edited.id), "ciphertext": .string(cipher.base64EncodedString()), "expected": .object(edited.body)]
            try JSONEncoder().encode(output).write(to: URL(fileURLWithPath: path + ".notebook"))
        }
    }
    func testStaleDeletedAndWrongKindRefuseWithoutMutating() throws {
        let original = notebook(); var current = original
        current.body["opaqueFuture"] = .bool(false)
        XCTAssertThrowsError(try current.editingJournal(expected: original, name: "Overwritten"))
        current = original; current.clock += 1
        XCTAssertThrowsError(try current.editingJournal(expected: original, name: "Overwritten"))
        current = original; current.deleted = true
        XCTAssertThrowsError(try current.editingJournal(expected: original, name: "Resurrected"))
        current = original; current.body["kind"] = .string("template")
        XCTAssertThrowsError(try current.editingJournal(expected: current, name: "Wrong kind"))
        XCTAssertEqual(original.title, "Original")
    }
    func testAckOnlyChangeAndUnknownAppearanceArePreserved() throws {
        var original = notebook(); original.body["cover"] = .string("future-cover"); original.body["color"] = .string("future-color"); original.dirty = true
        var current = original; current.dirty = false
        let edited = try current.editingJournal(expected: original, name: "Rename only")
        XCTAssertEqual(edited.body["cover"], .string("future-cover")); XCTAssertEqual(edited.body["color"], .string("future-color"))
        XCTAssertEqual(try current.editingJournal(expected: original), current, "No-op must not advance clock/dirty state")
    }
    func testInvalidPatchesAndClockOverflowFailClosed() throws {
        var original = notebook()
        for value in ["", " \n ", String(repeating: "a", count: 201)] { XCTAssertThrowsError(try original.editingJournal(expected: original, name: value)) }
        for value in ["red", "#123", "#12345g", "#123456\n"] { XCTAssertThrowsError(try original.editingJournal(expected: original, color: value)) }
        XCTAssertThrowsError(try original.editingJournal(expected: original, cover: "future"))
        XCTAssertThrowsError(try original.editingJournal(expected: original, subtitle: String(repeating: "a", count: 2001)))
        original.clock = ProtocolNumbers.maxWireInteger
        XCTAssertThrowsError(try original.editingJournal(expected: original, name: "Overflow"))
    }
    func testFrozenPlainEditorExpectedRecordRefusesSilentRebase() throws {
        var loaded = VaultRecord(id: "public-plain-editor", clock: 12, body: ["bodyText": .string("Loaded text"), "bodyJson": .string(try VaultRecord.plainDocument("Loaded text")), "chapterNativePlain": .bool(true)], dirty: true)
        XCTAssertTrue(loaded.editablePlainText)
        var acknowledged = loaded; acknowledged.dirty = false
        XCTAssertNoThrow(try acknowledged.requiringUnchanged(expected: loaded))
        var otherWriter = acknowledged; otherWriter.clock += 1
        otherWriter.body["bodyJson"] = .string(try VaultRecord.plainDocument("Other writer text"))
        XCTAssertThrowsError(try otherWriter.requiringUnchanged(expected: loaded))
        otherWriter.clock = loaded.clock // Even an equal-clock different body must refuse.
        XCTAssertThrowsError(try otherWriter.requiringUnchanged(expected: loaded))
        var deleted = loaded; deleted.deleted = true
        XCTAssertThrowsError(try deleted.requiringUnchanged(expected: loaded))
        loaded.clock += 1; loaded.body["bodyJson"] = .string(try VaultRecord.plainDocument("Own committed text"))
        var ownAcknowledged = loaded; ownAcknowledged.dirty = false
        XCTAssertNoThrow(try ownAcknowledged.requiringUnchanged(expected: loaded))
    }
    func testRichEntryMovePreservesAllContentAndRefusesStaleOrDeletedTargets() throws {
        let fixtureURL = try XCTUnwrap(Bundle.module.url(forResource: "rich-document", withExtension: "json"))
        let fixture = try JSONDecoder().decode([String: JSONValue].self, from: Data(contentsOf: fixtureURL))
        let raw = String(decoding: try JSONEncoder().encode(fixture["original"]!), as: UTF8.self)
        let original = VaultRecord(id: "native-moved-entry", clock: 12, body: ["journalId": .string("original"), "bodyJson": .string(raw), "labels": .array([.string("private label")]), "createdAt": .number(1), "unknownFuture": .object(["preserve": .bool(true)])], dirty: true)
        let target = VaultRecord(id: "destination-record", clock: 1, body: ["kind": .string("journal"), "journalId": .string("public-destination")])
        let moved = try original.movingEntry(expected: original, to: target, now: Date(timeIntervalSince1970: 100))
        XCTAssertEqual(moved.journalID, "public-destination"); XCTAssertEqual(moved.clock, 100000); XCTAssertTrue(moved.dirty)
        for key in ["bodyJson", "labels", "createdAt", "unknownFuture"] { XCTAssertEqual(moved.body[key], original.body[key]) }
        XCTAssertEqual(try moved.movingEntry(expected: moved, to: target), moved)
        var stale = original; stale.clock += 1; XCTAssertThrowsError(try stale.movingEntry(expected: original, to: target))
        var deleted = target; deleted.deleted = true; XCTAssertThrowsError(try original.movingEntry(expected: original, to: deleted))
        var wrong = target; wrong.body["kind"] = .string("template"); XCTAssertThrowsError(try original.movingEntry(expected: original, to: wrong))
        var overflow = original; overflow.clock = ProtocolNumbers.maxWireInteger; XCTAssertThrowsError(try overflow.movingEntry(expected: overflow, to: target))
        var acknowledged = original; acknowledged.dirty = false; XCTAssertNoThrow(try acknowledged.requiringUnchanged(expected: original))
        let pending = RichDraft(entryID: original.id, path: [0,0], expectedDocument: raw, text: "After move")
        XCTAssertEqual(try pending.applying(to: moved).journalID, moved.journalID)
        if let path = ProcessInfo.processInfo.environment["CHAPTER_NATIVE_OUTPUT"] {
            let identity = try VaultIdentity(seed: RecoveryPhrase.seed("legal winner thank year wave sausage worth useful legal winner thank yellow"))
            let cipher = try VaultCipher.sealRecord(JSONEncoder().encode(moved.body), key: identity.dataKey, id: moved.id)
            try JSONEncoder().encode(["id":moved.id,"record":cipher.base64EncodedString()]).write(to: URL(fileURLWithPath: path + ".entry-move"))
        }
    }

}
