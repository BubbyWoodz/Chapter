// SPDX-License-Identifier: AGPL-3.0-or-later
import XCTest
import CryptoKit
@testable import ChapterCore
final class LiveThemeTests: XCTestCase {
    func testWebToNativeOfflineRestartAndNativeToWebAgainstRealRelay() async throws {
        guard let base=ProcessInfo.processInfo.environment["CHAPTER_NATIVE_LIVE_URL"] else { throw XCTSkip("Separate hosted live TLS/Postgres gate") }
        let relay=Relay(address:try ServerAddress(base));defer { relay.cancel() }
        let identity=try VaultIdentity(seed:RecoveryPhrase.seed("legal winner thank year wave sausage worth useful legal winner thank yellow"))
        let token=try await relay.authenticate(identity)
        var state=VaultSnapshot(),cursor:Int64=0,finished=false
        for _ in 0..<100 {
            let page=try await relay.pull(since:cursor,token:token);cursor=page.cursor
            for item in page.entries where item.entry_id=="public-live-appearance" {
                let cipher=try XCTUnwrap(Data(base64Encoded:item.ciphertext))
                let body=try JSONDecoder().decode([String:JSONValue].self,from:VaultCipher.openRecord(cipher,key:identity.dataKey,id:item.entry_id))
                state.merge(VaultRecord(id:item.entry_id,clock:item.lww_clock,deleted:item.deleted,body:body))
            }
            if !page.more { finished=true;break }
        }
        XCTAssertTrue(finished);XCTAssertEqual(state.appearance,try SharedAppearance(mode:"light",palette:"sea",skin:"forest"))
        let stale=try XCTUnwrap(state.appearanceRecord)
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:directory) }
        let disk=EncryptedSnapshotStore(directory:directory,namespace:"live-theme",key:SymmetricKey(data:Data(repeating:8,count:32)))
        // No network calls while editing/persisting: the durable dirty record is
        // reloaded before the next actual network operation.
        try state.setAppearance(SharedAppearance(mode:"dark",palette:"moss",skin:"forest"),now:Date(timeIntervalSince1970:1))
        try disk.save(state);state=try disk.load()
        try state.setAppearance(SharedAppearance(mode:"dark",palette:"plum",skin:"lavender"),now:Date(timeIntervalSince1970:1))
        try disk.save(state);state=try disk.load()
        XCTAssertEqual(state.appearanceRecord?.clock,1001);XCTAssertTrue(try XCTUnwrap(state.appearanceRecord).dirty)
        let sent=try XCTUnwrap(state.appearanceRecord)
        let results=try await relay.push([sent],identity:identity,token:token)
        XCTAssertTrue(results.allSatisfy(\.applied))
        let rejected=try await relay.push([stale],identity:identity,token:token)
        XCTAssertFalse(try XCTUnwrap(rejected.first).applied,"Original older-client write must not replace native choice")
        state.acknowledge(sent);try disk.save(state)
        XCTAssertFalse(try XCTUnwrap(disk.load().appearanceRecord).dirty)
        XCTAssertEqual(state.appearanceRecord?.body["settings"]?["unknownFuture"],.object(["preserve":.bool(true)]))
    }
}
