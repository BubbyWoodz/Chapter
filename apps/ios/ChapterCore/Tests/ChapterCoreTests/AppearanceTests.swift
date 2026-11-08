// SPDX-License-Identifier: AGPL-3.0-or-later
import XCTest
import CryptoKit
@testable import ChapterCore
final class AppearanceTests: XCTestCase {
    func fixture() throws -> VaultRecord {
        let url=try XCTUnwrap(Bundle.module.url(forResource:"web-theme-v1",withExtension:"json"))
        let wire=try JSONDecoder().decode(JSONValue.self,from:Data(contentsOf:url))
        let identity=try VaultIdentity(seed:RecoveryPhrase.seed("legal winner thank year wave sausage worth useful legal winner thank yellow"))
        let id=try XCTUnwrap(wire["entry_id"].string)
        let plain=try VaultCipher.openRecord(XCTUnwrap(Data(base64Encoded:XCTUnwrap(wire["ciphertext"].string))),key:identity.dataKey,id:id)
        return VaultRecord(id:id,clock:100,body:try JSONDecoder().decode([String:JSONValue].self,from:plain))
    }
    func testWebSettingsNativeEditRestartAndReverseCiphertext() throws {
        var state=VaultSnapshot();state.records=[try fixture()]
        XCTAssertEqual(state.appearance,try SharedAppearance(mode:"light",palette:"sea",skin:"forest"))
        let before=state.records[0]
        try state.setAppearance(SharedAppearance(mode:"dark",palette:"plum",skin:"lavender"),now:Date(timeIntervalSince1970:1))
        XCTAssertEqual(state.records[0].id,before.id);XCTAssertEqual(state.records[0].body["settings"]?["unknownFuture"],.object(["preserve":.bool(true)]))
        XCTAssertEqual(state.records[0].body["settings"]?["enabled"],.bool(false));XCTAssertTrue(state.records[0].dirty)
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:directory) }
        let disk=EncryptedSnapshotStore(directory:directory,namespace:"theme",key:SymmetricKey(data:Data(repeating:9,count:32)))
        try disk.save(state);XCTAssertEqual(try disk.load(),state)
        if let path=ProcessInfo.processInfo.environment["CHAPTER_NATIVE_OUTPUT"] {
            let row=state.records[0]
            let identity=try VaultIdentity(seed:RecoveryPhrase.seed("legal winner thank year wave sausage worth useful legal winner thank yellow"))
            let cipher=try VaultCipher.sealRecord(JSONEncoder().encode(row.body),key:identity.dataKey,id:row.id)
            let output:[String:JSONValue] = ["id":.string(row.id),"ciphertext":.string(cipher.base64EncodedString()),"expected":.object(row.body)]
            try JSONEncoder().encode(output).write(to:URL(fileURLWithPath:path+".theme"))
        }
    }
    func testUnknownVersionAndOverflowPreserveAllData() throws {
        var state=VaultSnapshot();var row=try fixture()
        row.body["settings"] = .object(["chapterAppearance":.object(["v":.number(2),"opaque":.string("KEEP")]),"apiSecret":.string("PUBLIC-TEST-NOT-A-SECRET")])
        state.records=[row];let before=state
        XCTAssertThrowsError(try state.setAppearance(.standard));XCTAssertEqual(state,before)
        state.records[0]=try fixture();state.records[0].clock=ProtocolNumbers.maxWireInteger;let overflow=state
        XCTAssertThrowsError(try state.setAppearance(.standard));XCTAssertEqual(state,overflow)
    }
    func testCatalogAllPalettesSkinsModesAndDisabledBootstrap() throws {
        for skin in SharedAppearance.skins { for palette in SharedAppearance.palettes { for mode in SharedAppearance.modes {
            let preference=try SharedAppearance(mode:mode,palette:palette,skin:skin)
            for dark in [true,false] { for name in ["paper","surface","ink","ink-2","ink-3","line"] {
                XCTAssertNotNil(AppearanceCatalog.tokens(preference,dark:dark)[name].string)
            }}
        }}}
        var state=VaultSnapshot();try state.setAppearance(.standard)
        XCTAssertEqual(state.records[0].kind,"aiSettings");XCTAssertEqual(state.records[0].body["settings"]?["enabled"],.bool(false))
    }
    func testEqualClockConflictRetainsBothAndExplicitReapplyPreservesCurrentSecrets() throws {
        var state=VaultSnapshot();var local=try fixture();local.dirty=true
        var settings:[String:JSONValue]=[:]
        if case .object(let original)=local.body["settings"] { settings=original }
        settings["anthropic"] = .object(["apiKey":.string("PUBLIC-TEST-NOT-A-SECRET"),"model":.string("future-model")])
        var pref:[String:JSONValue]=[:]
        if case .object(let value)=settings["chapterAppearance"] { pref=value }
        pref["futureDensity"] = .string("keep");settings["chapterAppearance"] = .object(pref);local.body["settings"] = .object(settings)
        state.records=[local];var remote=local;remote.dirty=false
        remote.body["settings"] = .object(["chapterAppearance":SharedAppearance.standard.value])
        state.merge(remote);XCTAssertEqual(state.records,[local]);XCTAssertEqual(state.conflicts,[remote])
        try state.setAppearance(.standard,now:Date(timeIntervalSince1970:0))
        XCTAssertEqual(state.records[0].clock,101);XCTAssertEqual(state.conflicts,[remote])
        XCTAssertEqual(state.records[0].body["settings"]?["anthropic"],settings["anthropic"])
        XCTAssertEqual(state.records[0].body["settings"]?["chapterAppearance"]["futureDensity"],.string("keep"))
    }
    func testBackupPreparationFailureDoesNotCommitOrRegenerateData() throws {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:directory) }
        let disk=EncryptedSnapshotStore(directory:directory,namespace:"existing",key:SymmetricKey(data:Data(repeating:9,count:32)))
        var old=VaultSnapshot();old.records=[try fixture()];try disk.save(old)
        let file=directory.appendingPathComponent("existing.vault"),bytes=try Data(contentsOf:file)
        disk.prepareWriteForTesting={ throw ChapterError.storage }
        var next=old;try next.setAppearance(.standard)
        XCTAssertThrowsError(try disk.save(next));XCTAssertEqual(try Data(contentsOf:file),bytes);XCTAssertEqual(try disk.load(),old)
        disk.prepareWriteForTesting=nil;try disk.save(next);XCTAssertEqual(try disk.load(),next)
    }
}
