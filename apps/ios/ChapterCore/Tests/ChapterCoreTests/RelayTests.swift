// SPDX-License-Identifier: AGPL-3.0-or-later
import XCTest
import CryptoKit
@testable import ChapterCore

private final class FixtureProtocol: URLProtocol {
    static let lock = NSLock()
    static var handler: ((URLRequest) throws -> (Int, Data))?
    static func install(_ value: @escaping (URLRequest) throws -> (Int, Data)) {
        lock.lock(); defer { lock.unlock() }; handler = value
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock(); let action = Self.handler; Self.lock.unlock()
        do {
            let (code, body) = try XCTUnwrap(action)(request)
            let response = try XCTUnwrap(HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json", "Content-Length": "\(body.count)"]))
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body); client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
final class RelayTests: XCTestCase {
    private func relay() throws -> Relay {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [FixtureProtocol.self]
        return Relay(address: try ServerAddress("https://fixture.invalid/prefix"), configuration: config)
    }
    private func requestBody(_ request: URLRequest) throws -> Data {
        var body = request.httpBody ?? Data()
        if body.isEmpty, let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while true {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count >= 0 else { throw ChapterError.corruptData }
                if count == 0 { break }; body.append(contentsOf: buffer.prefix(count))
            }
        }
        return body
    }
    private func requestJSON(_ request: URLRequest) throws -> [String: String] {
        try JSONDecoder().decode([String: String].self, from: requestBody(request))
    }
    func testMediaDeleteRequiresOriginalEmpty204AndPreservesHTTPFailures() async throws {
        let token=String(repeating:"A",count:43),id=String(repeating:"a",count:32)
        for status in [200,202,204,500,503] {
            FixtureProtocol.install { request in
                XCTAssertEqual(request.httpMethod,"DELETE");XCTAssertEqual(request.url?.path,"/prefix/v1/media/"+id)
                XCTAssertEqual(request.value(forHTTPHeaderField:"Authorization"),"Bearer "+token)
                return (status,Data())
            }
            let client=try relay();defer{client.cancel()}
            do {try await client.deleteMedia(id:id,token:token);XCTAssertEqual(status,204,"Unexpected success must not retire deletion intent")}
            catch ChapterError.http(let code) {XCTAssertEqual(code,status);XCTAssertTrue([500,503].contains(status))}
            catch ChapterError.corruptData {XCTAssertTrue([200,202].contains(status))}
        }
        var requests=0
        FixtureProtocol.install {_ in requests+=1;return (204,Data())}
        let client=try relay();defer{client.cancel()}
        for invalid in ["../another-owner",String(repeating:"x",count:65),""] {
            do {try await client.deleteMedia(id:invalid,token:token);XCTFail("Unsafe ID accepted")}catch{}
        }
        do {try await client.deleteMedia(id:id,token:"injected\r\nHeader:value");XCTFail("Unsafe token accepted")}catch{}
        XCTAssertEqual(requests,0)
    }
    func testRepairRestoresOnlyMissingOriginalChunkAndNeverOverwritesDifferentCiphertext() async throws {
        let dir=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:dir)}
        let files=try EncryptedMediaFiles(directory:dir,namespace:"repair-http"),source=dir.appendingPathComponent("public")
        try Data([7]).write(to:source);let id=String(repeating:"a",count:32),key=Data(repeating:7,count:32),token=String(repeating:"A",count:43)
        let upload=try files.stage(source:source,id:id,name:"Public",mime:"application/octet-stream",key:key)
        let cache=MediaCache(id:id,chunks:upload.chunks,cipherBytes:upload.cipherBytes),cipher=try files.read(id:id,index:0)
        for different in [false,true] {
            var writes=0
            FixtureProtocol.install {request in
                if request.httpMethod=="GET",request.url!.path.hasSuffix("/chunks/0") {return different ? (200,Data(repeating:0,count:cipher.count)):(404,Data())}
                if request.httpMethod=="GET" {return (200,try JSONSerialization.data(withJSONObject:["media_id":id,"chunks":1,"bytes":cipher.count]))}
                XCTAssertEqual(request.httpMethod,"PUT");writes+=1;XCTAssertEqual(try self.requestBody(request),cipher)
                return (200,try JSONSerialization.data(withJSONObject:["media_id":id,"chunk":0]))
            }
            let client=try relay();defer{client.cancel()}
            do {let receipt=try await client.repairMedia(cache,files:files,mediaKey:key,token:token);XCTAssertFalse(different);XCTAssertEqual(receipt.media,cache)}
            catch ChapterError.corruptData {XCTAssertTrue(different)}
            XCTAssertEqual(writes,different ? 0:1)
        }
    }
    func testTypedDeleteReceiptCannotConfirmDifferentObject() async throws {
        FixtureProtocol.install {_ in (204,Data())}
        let client=try relay();defer{client.cancel()}
        let receipt=try await client.deleteMediaWithReceipt(id:String(repeating:"b",count:32),token:String(repeating:"A",count:43))
        var state=VaultSnapshot();state.mediaCache=[MediaCache(id:String(repeating:"a",count:32),chunks:1,cipherBytes:42)]
        let queued=try state.queueMediaPurge(state.reviewMediaPurge(state.mediaCache![0])),sent=try state.beginMediaPurge(queued)
        XCTAssertThrowsError(try state.confirmMediaPurge(sent,receipt:receipt));XCTAssertEqual(try state.mediaPurgeIntents(),[sent])
        let bound=try await client.deleteMediaForPurge(sent,token:String(repeating:"A",count:43))
        let retry=try state.beginMediaPurge(sent)
        XCTAssertThrowsError(try state.confirmMediaPurge(retry,receipt:bound),"An older successful request cannot confirm a newer retry revision")
        let current=try await client.deleteMediaForPurge(retry,token:String(repeating:"A",count:43))
        XCTAssertEqual(try state.confirmMediaPurge(retry,receipt:current).phase,.confirmed)
    }
    func testActualRegistrationAndRawChallengeTranscriptWithFutureResponseFields() async throws {
        let id = try VaultIdentity(seed: RecoveryPhrase.seed("legal winner thank year wave sausage worth useful legal winner thank yellow"))
        let challenge = Data(repeating: 7, count: 32), token = String(repeating: "A", count: 43)
        var paths: [String] = []
        FixtureProtocol.install { request in
            let path = request.url!.path; paths.append(path)
            XCTAssertEqual(request.httpMethod, "POST"); XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            let json = try self.requestJSON(request)
            let response: [String: Any]
            switch path {
            case "/prefix/v1/register":
                XCTAssertEqual(json["owner_pubkey"], id.ownerPublic.base64EncodedString())
                XCTAssertEqual(json["device_pubkey"], id.deviceSigning.publicKey.rawRepresentation.base64EncodedString())
                XCTAssertEqual(json["owner_sign_pubkey"], id.ownerSigning.publicKey.rawRepresentation.base64EncodedString())
                let deviceMessage = Data("mneme:register:".utf8) + id.ownerPublic + id.deviceSigning.publicKey.rawRepresentation
                let ownerMessage = Data("mneme:bind-device:v1:".utf8) + id.ownerPublic + id.ownerSigning.publicKey.rawRepresentation + id.deviceSigning.publicKey.rawRepresentation
                XCTAssertTrue(id.deviceSigning.publicKey.isValidSignature(try XCTUnwrap(Data(base64Encoded: XCTUnwrap(json["signature"]))), for: deviceMessage))
                XCTAssertTrue(id.ownerSigning.publicKey.isValidSignature(try XCTUnwrap(Data(base64Encoded: XCTUnwrap(json["owner_signature"]))), for: ownerMessage))
                response = ["owner_id": id.ownerID, "device_id": id.deviceID, "status": "approved", "future": true]
            case "/prefix/v1/auth/challenge":
                XCTAssertEqual(json, ["device_id": id.deviceID])
                response = ["challenge": challenge.base64EncodedString(), "expires_at": "2026-01-01T00:00:00Z", "future": 1]
            case "/prefix/v1/auth/verify":
                XCTAssertEqual(json["device_id"], id.deviceID); XCTAssertEqual(json["challenge"], challenge.base64EncodedString())
                XCTAssertTrue(id.deviceSigning.publicKey.isValidSignature(try XCTUnwrap(Data(base64Encoded: XCTUnwrap(json["signature"]))), for: challenge))
                response = ["owner_id": id.ownerID, "token": token, "expires_at": "2026-01-01T00:00:00Z", "future": ["ok": true]]
            default: throw ChapterError.authentication
            }
            return (200, try JSONSerialization.data(withJSONObject: response))
        }
        let client = try relay(); defer { client.cancel() }
        let received = try await client.authenticate(id)
        XCTAssertEqual(received, token)
        XCTAssertEqual(paths, ["/prefix/v1/register", "/prefix/v1/auth/challenge", "/prefix/v1/auth/verify"])
    }
    func testAuthenticationRejectsWrongOwnerPendingMalformedChallengeAndHeaderToken() async throws {
        let id = try VaultIdentity(seed: Data(repeating: 0, count: 64))
        for scenario in ["wrong-owner", "pending", "bad-challenge", "header-token"] {
            var requests = 0
            FixtureProtocol.install { request in
                requests += 1
                let response: [String: Any]
                switch request.url!.lastPathComponent {
                case "register": response = ["owner_id": scenario == "wrong-owner" ? "wrong" : id.ownerID, "device_id": id.deviceID, "status": scenario == "pending" ? "pending" : "approved"]
                case "challenge": response = ["challenge": Data(repeating: 0, count: scenario == "bad-challenge" ? 31 : 32).base64EncodedString()]
                case "verify": response = ["owner_id": id.ownerID, "token": "injected\r\nHeader: value"]
                default: throw ChapterError.authentication
                }
                return (200, try JSONSerialization.data(withJSONObject: response))
            }
            let client = try relay()
            do { _ = try await client.authenticate(id); XCTFail("Accepted \(scenario)") } catch {}
            client.cancel()
            XCTAssertEqual(requests, scenario == "header-token" ? 3 : scenario == "bad-challenge" ? 2 : 1)
        }
    }
    func testPullAuthenticatesOnlyConfiguredHostAndRejectsUntrustedClock() async throws {
        FixtureProtocol.install { request in
            XCTAssertEqual(request.url?.absoluteString, "https://fixture.invalid/prefix/v1/sync/pull")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer " + String(repeating: "A", count: 43))
            return (200, Data(#"{"entries":[{"entry_id":"x","lww_clock":9223372036854775807,"ciphertext":"AA==","deleted":false}],"cursor":1,"more":false}"#.utf8))
        }
        let client = try relay(); defer { client.cancel() }
        do { _ = try await client.pull(since: 0, token: String(repeating: "A", count: 43)); XCTFail("Accepted unsafe clock") } catch {}
    }
    func testTokenValidationRejectsEveryControlByteIncludingFinalNewline() {
        let valid = String(repeating: "A", count: 43)
        XCTAssertTrue(Relay.validToken(valid)); XCTAssertTrue(Relay.validToken(String(repeating: "-_09azAZ", count: 5)))
        for byte in UInt8(0)...UInt8(32) {
            XCTAssertFalse(Relay.validToken(valid + String(UnicodeScalar(byte))))
        }
        for invalid in ["short", valid + "é", valid + ":", String(repeating: "A", count: 513)] {
            XCTAssertFalse(Relay.validToken(invalid))
        }
    }

    func testMediaRawCipherUploadFailureRetryAndLostCompleteAcknowledgment() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appendingPathComponent("selected"), key = Data(repeating: 3, count: 32), id = "0123456789abcdef"
        try Data(repeating: 77, count: MediaLimits.chunkBytes + 17).write(to: source)
        let files = try EncryptedMediaFiles(directory: dir, namespace: "retry")
        let upload = try files.stage(source: source, id: id, name: "PRIVATE-FILENAME", mime: "image/png", key: key)
        var chunks: [Int: Data] = [:], failedOnce = false, finalized = false, puts = 0, completions = 0
        FixtureProtocol.install { request in
            XCTAssertEqual(request.url?.host, "fixture.invalid")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer " + String(repeating: "A", count: 43))
            let path = request.url!.path
            let json: [String: Any]
            if request.httpMethod == "GET", !path.contains("/chunks/") {
                if !finalized { return (404, Data()) }
                json = ["media_id":id,"chunks":upload.chunks,"bytes":upload.cipherBytes]
            } else if request.httpMethod == "PUT" {
                puts += 1
                XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/octet-stream")
                let index = try XCTUnwrap(Int(request.url!.lastPathComponent)), data = try self.requestBody(request)
                XCTAssertEqual(data, try files.read(id: id, index: index))
                XCTAssertNil(data.range(of: Data(upload.name.utf8)))
                if index == 1, !failedOnce { failedOnce = true; return (503, Data()) }
                chunks[index] = data; json = ["media_id":id,"chunk":index]
            } else if path.hasSuffix("/complete") {
                completions += 1
                let body = try JSONDecoder().decode([String:Int64].self, from: self.requestBody(request))
                XCTAssertEqual(body["bytes"], upload.cipherBytes)
                XCTAssertEqual(body["chunks"], Int64(upload.chunks))
                XCTAssertEqual(chunks.values.reduce(Int64(0)) { $0 + Int64($1.count) }, upload.cipherBytes)
                finalized = true; return (500, Data()) // Server committed; acknowledgment was lost.
            } else {
                return (200, try XCTUnwrap(chunks[Int(request.url!.lastPathComponent)!]))
            }
            return (200, try JSONSerialization.data(withJSONObject: json))
        }
        let client = try relay(); defer { client.cancel() }
        let token = String(repeating: "A", count: 43)
        for _ in 0..<2 {
            do { try await client.uploadMedia(upload, files: files, mediaKey: key, token: token); XCTFail("Injected failure not propagated") } catch {}
        }
        XCTAssertTrue(finalized); let uploadsBeforeRecovery = puts
        try await client.uploadMedia(upload, files: files, mediaKey: key, token: token)
        XCTAssertEqual(puts, uploadsBeforeRecovery, "Lost-ack recovery must not rewrite finalized media or consume quota twice")
        XCTAssertEqual(completions, 1)
        XCTAssertEqual(try files.read(id: id, index: 0), chunks[0])
    }
    func testMediaCollisionMetadataAndLocalTamperingRefuseFinalization() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appendingPathComponent("selected"), key = Data(repeating: 3, count: 32), id = "0123456789abcdef"
        try Data([1,2,3]).write(to: source)
        let files = try EncryptedMediaFiles(directory: dir, namespace: "tamper")
        let upload = try files.stage(source: source, id: id, name: "private", mime: "x", key: key)
        for scenario in ["wrong-id", "wrong-bytes", "tampered-cipher"] {
            if scenario == "tampered-cipher" { var cipher = try files.read(id:id,index:0); cipher[cipher.count-1] ^= 1; try files.writeDownloaded(cipher,id:id,index:0) }
            var requests = 0
            FixtureProtocol.install { request in
                requests += 1; XCTAssertEqual(request.httpMethod, "GET")
                if scenario == "tampered-cipher" { return (404, Data()) }
                return (200, try JSONSerialization.data(withJSONObject: ["media_id":scenario == "wrong-id" ? "another-object-id" : id, "chunks":upload.chunks, "bytes":upload.cipherBytes+1]))
            }
            let client = try relay()
            do { try await client.uploadMedia(upload, files:files, mediaKey:key, token:String(repeating:"A",count:43)); XCTFail("Accepted \(scenario)") } catch {}
            client.cancel(); XCTAssertEqual(requests,1)
        }
    }
    func testPushRejectsMissingDuplicateOrForeignAcknowledgments() async throws {
        let identity = try VaultIdentity(seed: Data(repeating: 0, count: 64))
        let records = [VaultRecord(id: "one", clock: 1, body: [:], dirty: true), VaultRecord(id: "two", clock: 1, body: [:], dirty: true)]
        for json in [
            #"{"results":[{"entry_id":"one","applied":true}]}"#,
            #"{"results":[{"entry_id":"one","applied":true},{"entry_id":"one","applied":true}]}"#,
            #"{"results":[{"entry_id":"one","applied":true},{"entry_id":"foreign","applied":true}]}"#
        ] {
            FixtureProtocol.install { _ in (200, Data(json.utf8)) }
            let client = try relay()
            do { _ = try await client.push(records, identity:identity, token:String(repeating:"A",count:43)); XCTFail("Accepted malformed acknowledgments") } catch {}
            client.cancel()
        }
    }
}
