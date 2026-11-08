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
    private func requestJSON(_ request: URLRequest) throws -> [String: String] {
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
        return try JSONDecoder().decode([String: String].self, from: body)
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

}
