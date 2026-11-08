// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
import CryptoKit
import CommonCrypto
import Sodium

public enum ChapterError: Error, LocalizedError {
    case invalidPhrase, invalidURL, authentication, corruptData, unsupported, storage, http(Int)
    public var errorDescription: String? {
        switch self {
        case .invalidPhrase: return "Enter a valid 12-word English recovery phrase."
        case .invalidURL: return "Use an HTTPS server URL without credentials, query or fragment. Include any server path prefix."
        case .authentication: return "Authentication failed. Check the recovery phrase and server."
        case .corruptData: return "Data could not be authenticated. Nothing was overwritten."
        case .unsupported: return "This content or server version is not supported by this preview."
        case .storage: return "Secure local storage failed. Ensure a device passcode is set. Your changes have not been acknowledged as saved."
        case .http(let code): return "Server returned HTTP \(code). \(code == 403 ? "The vault may need operator approval." : code == 429 ? "Wait before retrying." : "")"
        }
    }
}

public struct VaultIdentity {
    public let dataKey: Data
    public let mediaKey: Data
    public let ownerPublic: Data
    public let ownerSigning: Curve25519.Signing.PrivateKey
    public let deviceSigning: Curve25519.Signing.PrivateKey
    public var ownerID: String { Data(SHA256.hash(data: ownerPublic)).base64URL }
    public var deviceID: String { Data(SHA256.hash(data: deviceSigning.publicKey.rawRepresentation)).base64URL }
    public init(seed: Data) throws {
        guard seed.count == 64 else { throw ChapterError.invalidPhrase }
        func derive(_ label: String) -> Data {
            Data(HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: seed), salt: Data("journal-v1".utf8), info: Data(label.utf8), outputByteCount: 32).withUnsafeBytes { Data($0) })
        }
        dataKey = derive("data"); mediaKey = derive("media")
        ownerPublic = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: derive("identity")).publicKey.rawRepresentation
        ownerSigning = try Curve25519.Signing.PrivateKey(rawRepresentation: derive("identity-sign"))
        deviceSigning = try Curve25519.Signing.PrivateKey(rawRepresentation: derive("device"))
    }
    public func registration() throws -> [String: String] {
        let device = deviceSigning.publicKey.rawRepresentation
        return ["owner_pubkey": ownerPublic.base64EncodedString(), "device_pubkey": device.base64EncodedString(),
                "signature": try deviceSigning.signature(for: Data("mneme:register:".utf8) + ownerPublic + device).base64EncodedString(),
                "owner_sign_pubkey": ownerSigning.publicKey.rawRepresentation.base64EncodedString(),
                "owner_signature": try ownerSigning.signature(for: Data("mneme:bind-device:v1:".utf8) + ownerPublic + ownerSigning.publicKey.rawRepresentation + device).base64EncodedString()]
    }
}

public enum RecoveryPhrase {
    static let words: [String] = {
        guard let url = Bundle.module.url(forResource: "english", withExtension: "json"),
              let data = try? Data(contentsOf: url), let list = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return list
    }()
    public static func normalize(_ input: String) -> String {
        input.split(whereSeparator: { $0.isWhitespace }).map { $0.lowercased() }.joined(separator: " ")
    }
    public static func seed(_ input: String) throws -> Data {
        let phrase = normalize(input)
        let parts = phrase.split(separator: " ").map(String.init)
        guard words.count == 2048, parts.count == 12 else { throw ChapterError.invalidPhrase }
        var bits: [UInt8] = []
        for word in parts {
            guard let index = words.firstIndex(of: word) else { throw ChapterError.invalidPhrase }
            bits += (0..<11).reversed().map { UInt8((index >> $0) & 1) }
        }
        var entropy = Data()
        for i in stride(from: 0, to: 128, by: 8) { entropy.append(bits[i..<i+8].reduce(0) { ($0 << 1) | $1 }) }
        let checksum = SHA256.hash(data: entropy).first! >> 4
        guard bits[128..<132].reduce(UInt8(0), { ($0 << 1) | $1 }) == checksum else { throw ChapterError.invalidPhrase }
        let password = Data(phrase.decomposedStringWithCompatibilityMapping.utf8)
        let salt = Data("mnemonic".utf8)
        var output = Data(count: 64)
        let status = output.withUnsafeMutableBytes { out in
            password.withUnsafeBytes { pass in salt.withUnsafeBytes { saltBytes in
                CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), pass.baseAddress!.assumingMemoryBound(to: Int8.self), password.count,
                                    saltBytes.baseAddress!.assumingMemoryBound(to: UInt8.self), salt.count,
                                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA512), 2048,
                                    out.baseAddress!.assumingMemoryBound(to: UInt8.self), 64)
            }}
        }
        guard status == kCCSuccess else { throw ChapterError.authentication }
        return output
    }
}

public enum VaultCipher {
    public static func seal(_ plaintext: Data, key: Data, aad: Data) throws -> Data {
        guard key.count == 32 else { throw ChapterError.corruptData }
        let encrypted: [UInt8]? = Sodium().aead.xchacha20poly1305ietf.encrypt(message: Array(plaintext), secretKey: Array(key), additionalData: Array(aad))
        guard let encrypted else { throw ChapterError.corruptData }
        return Data([1]) + Data(encrypted)
    }
    public static func open(_ envelope: Data, key: Data, aad: Data) throws -> Data {
        guard key.count == 32, envelope.count >= 41, envelope.first == 1,
              let value = Sodium().aead.xchacha20poly1305ietf.decrypt(nonceAndAuthenticatedCipherText: Array(envelope.dropFirst()), secretKey: Array(key), additionalData: Array(aad)) else { throw ChapterError.corruptData }
        return Data(value)
    }
    public static func sealRecord(_ data: Data, key: Data, id: String) throws -> Data {
        try seal(data, key: key, aad: Data("mneme:record:v1:\(id)".utf8))
    }
    public static func openRecord(_ data: Data, key: Data, id: String) throws -> Data {
        do { return try open(data, key: key, aad: Data("mneme:record:v1:\(id)".utf8)) }
        catch { return try open(data, key: key, aad: Data()) } // upstream pre-AAD compatibility
    }
    public static func openMediaChunk(_ data: Data, key: Data, id: String, index: Int, total: Int) throws -> Data {
        guard index >= 0, index < total else { throw ChapterError.corruptData }
        return try open(data, key: key, aad: Data("media:\(id):\(index)/\(total)".utf8))
    }
}

extension Data {
    public var base64URL: String { base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
    public var hex: String { map { String(format: "%02x", $0) }.joined() }
}
