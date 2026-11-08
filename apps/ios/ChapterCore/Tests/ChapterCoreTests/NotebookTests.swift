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
}
