// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

public struct ServerAddress: Equatable {
    public let url: URL
    public init(_ input: String) throws {
        guard var c = URLComponents(string: input.trimmingCharacters(in: .whitespacesAndNewlines)),
              c.scheme?.lowercased() == "https", let host = c.host, !host.isEmpty,
              c.user == nil, c.password == nil, c.query == nil, c.fragment == nil else { throw ChapterError.invalidURL }
        c.scheme = "https"
        while c.path.hasSuffix("/") { c.path.removeLast() }
        guard let url = c.url else { throw ChapterError.invalidURL }; self.url = url
    }
    public func endpoint(_ path: String) -> URL { url.appendingPathComponent(path) }
}

private final class NoRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil) // no credential forwarding, including same-host path redirects
    }
}
public struct PushResult: Decodable { public let entry_id: String; public let applied: Bool }
public struct PullRecord: Codable { public let entry_id: String; public let lww_clock: Int64; public let ciphertext: String; public let deleted: Bool }
public struct PullPage: Decodable {
    public let entries: [PullRecord]; public let cursor: Int64; public let more: Bool
    func validate(since: Int64) throws {
        try ProtocolNumbers.validate(since); try ProtocolNumbers.validate(cursor)
        guard cursor >= since, entries.count <= 500,
              entries.isEmpty ? (cursor == since && !more) : cursor > since else { throw ChapterError.corruptData }
        for record in entries { try ProtocolNumbers.validate(record.lww_clock) }
    }
}
public final class Relay {
    public let address: ServerAddress
    private let session: URLSession
    private let delegate = NoRedirects()
    public convenience init(address: ServerAddress) {
        self.init(address: address, configuration: .ephemeral)
    }
    // Internal injection is for deterministic URLProtocol tests, not a public transport bypass.
    init(address: ServerAddress, configuration config: URLSessionConfiguration) {
        self.address = address
        config.urlCache = nil; config.httpCookieStorage = nil; config.httpShouldSetCookies = false
        config.urlCredentialStorage = nil; config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 30; config.timeoutIntervalForResource = 120
        session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
    }
    public func cancel() { session.invalidateAndCancel() }
    static func validToken(_ token: String) -> Bool {
        let bytes = token.utf8
        return (32...512).contains(bytes.count) && bytes.allSatisfy {
            (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95
        }
    }
    private func request(_ path: String, method: String = "POST", body: Data? = nil, token: String? = nil, maxBytes: Int = 32 * 1024 * 1024) async throws -> Data {
        var req = URLRequest(url: address.endpoint(path))
        req.httpMethod = method; req.httpBody = body
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token {
            guard Self.validToken(token) else { throw ChapterError.authentication }
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        // Streaming bounds an untrusted response before it fills memory.
        let (bytes, response) = try await session.bytes(for: req)
        guard let response = response as? HTTPURLResponse else { throw ChapterError.authentication }
        guard (200..<300).contains(response.statusCode) else { throw ChapterError.http(response.statusCode) }
        if response.expectedContentLength > Int64(maxBytes) { throw ChapterError.corruptData }
        var result = Data()
        for try await byte in bytes {
            guard result.count < maxBytes else { throw ChapterError.corruptData }
            result.append(byte)
        }
        return result
    }
    public func authenticate(_ identity: VaultIdentity) async throws -> String {
        let registration = try await request("v1/register", body: JSONEncoder().encode(identity.registration()))
        struct Registration: Decodable { let owner_id, device_id, status: String }
        let result = try JSONDecoder().decode(Registration.self, from: registration)
        guard result.owner_id == identity.ownerID, result.device_id == identity.deviceID else { throw ChapterError.authentication }
        guard result.status == "approved" else { throw ChapterError.http(403) }
        let challenge = try await request("v1/auth/challenge", body: JSONEncoder().encode(["device_id": identity.deviceID]))
        struct Challenge: Decodable { let challenge: String }
        let fields = try JSONDecoder().decode(Challenge.self, from: challenge)
        let encoded = fields.challenge
        guard let bytes = Data(base64Encoded: encoded), bytes.count == 32 else { throw ChapterError.authentication }
        let signature = try identity.deviceSigning.signature(for: bytes).base64EncodedString()
        let verified = try await request("v1/auth/verify", body: JSONEncoder().encode(["device_id": identity.deviceID, "challenge": encoded, "signature": signature]))
        struct Session: Decodable { let owner_id, token: String }
        let auth = try JSONDecoder().decode(Session.self, from: verified)
        guard auth.owner_id == identity.ownerID,
              Self.validToken(auth.token) else { throw ChapterError.authentication }
        return auth.token
    }
    public func pull(since: Int64, token: String) async throws -> PullPage {
        try ProtocolNumbers.validate(since)
        let data = try await request("v1/sync/pull", body: JSONEncoder().encode(["since": since, "limit": 100]), token: token)
        let page = try JSONDecoder().decode(PullPage.self, from: data)
        try page.validate(since: since)
        return page
    }
    public func push(_ records: [VaultRecord], identity: VaultIdentity, token: String) async throws -> [PushResult] {
        guard records.count <= 100 else { throw ChapterError.unsupported }
        let entries = try records.map { record -> PullRecord in
            try ProtocolNumbers.validate(record.clock)
            let plain = try JSONEncoder().encode(record.body)
            let cipher = try VaultCipher.sealRecord(plain, key: identity.dataKey, id: record.id)
            return PullRecord(entry_id: record.id, lww_clock: record.clock, ciphertext: cipher.base64EncodedString(), deleted: record.deleted)
        }
        struct Results: Decodable { let results: [PushResult] }
        let data = try await request("v1/sync/push", body: JSONEncoder().encode(["entries": entries]), token: token)
        return try JSONDecoder().decode(Results.self, from: data).results
    }
    public func mediaChunk(id: String, index: Int, token: String) async throws -> Data {
        guard id.range(of: "^[A-Za-z0-9_-]{1,128}$", options: .regularExpression) != nil, index >= 0 else { throw ChapterError.corruptData }
        return try await request("v1/media/\(id)/chunks/\(index)", method: "GET", token: token, maxBytes: 2 * 1024 * 1024)
    }
    public func mediaChunks(id: String, token: String) async throws -> Int {
        guard id.range(of: "^[A-Za-z0-9_-]{1,128}$", options: .regularExpression) != nil else { throw ChapterError.corruptData }
        struct Meta: Decodable { let chunks: Int }
        let data = try await request("v1/media/\(id)", method: "GET", token: token)
        let n = try JSONDecoder().decode(Meta.self, from: data).chunks
        guard n > 0, n <= 512 else { throw ChapterError.unsupported }; return n
    }
}
