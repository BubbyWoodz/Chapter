// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
import CryptoKit
import Security

public enum DeviceKeychain {
    private static let service = "org.chapter.native.local-vault.v1"
    public static func key(for namespace: String, mayCreate: Bool) throws -> SymmetricKey {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: namespace, kSecAttrSynchronizable as String: false]
        var lookup = query
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(lookup as CFDictionary, &item)
        if status == errSecSuccess, let data = item as? Data, data.count == 32 { return SymmetricKey(data: data) }
        guard status == errSecItemNotFound, mayCreate else { throw ChapterError.storage }
        var random = Data(count: 32)
        guard random.withUnsafeMutableBytes({ SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!) }) == errSecSuccess,
              let control = SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly, .userPresence, nil) else { throw ChapterError.storage }
        var insertion = query
        insertion[kSecValueData as String] = random
        insertion[kSecAttrAccessControl as String] = control
        guard SecItemAdd(insertion as CFDictionary, nil) == errSecSuccess else { throw ChapterError.storage }
        return SymmetricKey(data: random)
    }
}

// Independent device key, not a wire-format change. Never migrates/modifies the web OPFS database.
public final class EncryptedSnapshotStore {
    public let namespace: String
    private let file: URL
    private let key: SymmetricKey
    private let aad: Data
    public static func namespace(server: URL, owner: String) -> String {
        Data(SHA256.hash(data: Data((server.absoluteString + "\n" + owner).utf8))).hex
    }
    public static func applicationDirectory() throws -> URL {
        let root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let dir = root.appendingPathComponent("ChapterVaults", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: dir.path)
        #endif
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        var protectedDir = dir; try protectedDir.setResourceValues(values)
        return dir
    }
    public static func open(server: URL, owner: String) throws -> EncryptedSnapshotStore {
        let namespace = Self.namespace(server: server, owner: owner)
        let dir = try applicationDirectory()
        let exists = FileManager.default.fileExists(atPath: dir.appendingPathComponent(namespace + ".vault").path)
        // Missing/inaccessible keys NEVER trigger regeneration over an existing snapshot.
        let key = try DeviceKeychain.key(for: namespace, mayCreate: !exists)
        return EncryptedSnapshotStore(directory: dir, namespace: namespace, key: key)
    }
    public init(directory: URL, namespace: String, key: SymmetricKey) {
        self.namespace = namespace; self.key = key
        file = directory.appendingPathComponent(namespace + ".vault")
        aad = Data("chapter:local-snapshot:v1:\(namespace)".utf8)
    }
    public func load() throws -> VaultSnapshot {
        guard FileManager.default.fileExists(atPath: file.path) else { return VaultSnapshot() }
        let sealed = try Data(contentsOf: file)
        do {
            let plain = try AES.GCM.open(AES.GCM.SealedBox(combined: sealed), using: key, authenticating: aad)
            var value = try JSONDecoder().decode(VaultSnapshot.self, from: plain)
            guard (1...3).contains(value.version) else { throw ChapterError.unsupported }
            value.version = 3 // Read v1 without rewriting; upgrade atomically on the next save.
            return value
        } catch { throw ChapterError.corruptData }
    }
    public func save(_ value: VaultSnapshot) throws {
        let plain = try JSONEncoder().encode(value)
        guard let data = try AES.GCM.seal(plain, using: key, authenticating: aad).combined else { throw ChapterError.storage }
        #if os(iOS)
        try data.write(to: file, options: [.atomic, .completeFileProtection])
        #else
        try data.write(to: file, options: .atomic)
        #endif
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        var target = file; try target.setResourceValues(values)
    }
}
