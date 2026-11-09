// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

public struct MediaUpload: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let chunks: Int
    public let cipherBytes: Int64
    public let plainBytes: Int
    public let name: String
    public let mime: String
    public func validate() throws {
        guard MediaLimits.validID(id), (0...MediaLimits.maximumPlainBytes).contains(plainBytes),
              chunks == max(1, (plainBytes + MediaLimits.chunkBytes - 1) / MediaLimits.chunkBytes),
              cipherBytes == Int64(plainBytes + chunks * 41) else { throw ChapterError.corruptData }
    }
    public var attributes: [String: JSONValue] {
        let kind = mime.hasPrefix("image/") ? "image" : mime.hasPrefix("video/") ? "video" : mime.hasPrefix("audio/") ? "audio" : "file"
        return ["id": .string(id), "kind": .string(kind), "mime": .string(mime), "name": .string(name), "bytes": .number(Double(plainBytes))]
    }
}
public struct MediaCache: Codable, Equatable {
    public let id: String
    public let chunks: Int
    public let cipherBytes: Int64
    public init(id: String, chunks: Int, cipherBytes: Int64) { self.id = id; self.chunks = chunks; self.cipherBytes = cipherBytes }
}
public enum MediaLimits {
    public static let chunkBytes = 1 << 20
    public static let maximumPlainBytes = 128 << 20
    public static func validID(_ id: String) -> Bool {
        let bytes = id.utf8
        return (16...64).contains(bytes.count) && bytes.allSatisfy { (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95 }
    }
}
/// Durable files contain ONLY original-protocol ciphertext. Names/MIME/outbox
/// state are in the encrypted snapshot; no plaintext durable media cache.
public final class EncryptedMediaFiles {
    private let root: URL
    public init(directory: URL, namespace: String) throws {
        guard !namespace.isEmpty, namespace.utf8.count <= 128, namespace.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95 }) else { throw ChapterError.storage }
        root = directory.appendingPathComponent("Media", isDirectory: true).appendingPathComponent(namespace, isDirectory: true)
        try Self.protectedDirectory(root)
    }
    public static func protectedDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
        #endif
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        var target = url; try target.setResourceValues(values)
    }
    private func folder(_ id: String) throws -> URL {
        guard MediaLimits.validID(id) else { throw ChapterError.corruptData }
        return root.appendingPathComponent(id, isDirectory: true)
    }
    private func file(_ id: String, _ index: Int) throws -> URL {
        guard (0..<512).contains(index) else { throw ChapterError.corruptData }
        return try folder(id).appendingPathComponent("\(index).chunk")
    }
    public func read(id: String, index: Int) throws -> Data {
        let url = try file(id, index), size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? -1
        guard (41...(2 << 20)).contains(size) else { throw ChapterError.corruptData }
        return try Data(contentsOf: url)
    }
    public func writeDownloaded(_ cipher: Data, id: String, index: Int) throws {
        guard (41...(2 << 20)).contains(cipher.count) else { throw ChapterError.corruptData }
        try Self.protectedDirectory(folder(id))
        let url = try file(id, index)
        #if os(iOS)
        try cipher.write(to: url, options: [.atomic, .completeFileProtection])
        #else
        try cipher.write(to: url, options: .atomic)
        #endif
        let handle = try FileHandle(forWritingTo: url); defer { try? handle.close() }
        try handle.synchronize()
    }
    /// Caller must first persist authenticated remote completion. Recheck the
    /// exact confirmed intent and every local protection immediately before I/O.
    /// Missing files are success on restart after a lost local completion write.
    public func removeConfirmedPurge(_ intent: MediaPurgeIntent, snapshot: VaultSnapshot) throws {
        guard intent.phase == .confirmed,
              try snapshot.mediaPurgeIntents().contains(intent) else { throw ChapterError.conflict }
        try snapshot.requireMediaPurgeUnreferenced(intent.media)
        let location = try folder(intent.media.id)
        if FileManager.default.fileExists(atPath: location.path) { try FileManager.default.removeItem(at: location) }
    }
    /// Used ONLY for this operation's unpublished, newly created staging object.
    public func discardUnpublished(id: String) throws { try FileManager.default.removeItem(at: folder(id)) }
    public func stage(source: URL, id: String, name: String, mime: String, key: Data) throws -> MediaUpload {
        let bytes = try source.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? -1
        guard (0...MediaLimits.maximumPlainBytes).contains(bytes), key.count == 32 else { throw ChapterError.unsupported }
        let destination = try folder(id)
        guard !FileManager.default.fileExists(atPath: destination.path) else { throw ChapterError.storage }
        try Self.protectedDirectory(destination)
        var successful = false
        defer { if !successful { try? FileManager.default.removeItem(at: destination) } }
        let handle = try FileHandle(forReadingFrom: source); defer { try? handle.close() }
        let count = max(1, (bytes + MediaLimits.chunkBytes - 1) / MediaLimits.chunkBytes)
        var cipherBytes: Int64 = 0
        for index in 0..<count {
            try Task.checkCancellation()
            let expected = min(MediaLimits.chunkBytes, bytes - index * MediaLimits.chunkBytes)
            let plain = try handle.read(upToCount: MediaLimits.chunkBytes) ?? Data()
            guard plain.count == expected else { throw ChapterError.corruptData }
            let cipher = try VaultCipher.seal(plain, key: key, aad: Data("media:\(id):\(index)/\(count)".utf8))
            try writeDownloaded(cipher, id: id, index: index); cipherBytes += Int64(cipher.count)
        }
        guard (try handle.read(upToCount: 1) ?? Data()).isEmpty else { throw ChapterError.corruptData }
        successful = true
        return MediaUpload(id: id, chunks: count, cipherBytes: cipherBytes, plainBytes: bytes, name: name, mime: mime)
    }
}
extension VaultSnapshot {
    public mutating func attach(_ upload: MediaUpload, entryID: String, expectedDocument: String) throws {
        guard let index = records.firstIndex(where: { $0.id == entryID }), records[index].kind == "entry", MediaLimits.validID(upload.id) else { throw ChapterError.conflict }
        try upload.validate()
        guard !(mediaUploads ?? []).contains(where: { $0.id == upload.id }) else { throw ChapterError.conflict }
        let updated = try records[index].editingRichDocument(expected: expectedDocument) { doc in try doc.appendMedia(upload.attributes) }
        // Publish locally only after every cipher chunk is durable. Sync gates
        // remote records on the outbox, and retries preserve the same nonce bytes.
        records[index] = updated
        var uploads = mediaUploads ?? []; uploads.append(upload); mediaUploads = uploads
    }
    public mutating func mediaUploaded(_ upload: MediaUpload) {
        guard mediaUploads?.contains(upload) == true else { return }
        mediaUploads = mediaUploads?.filter { $0.id != upload.id }
        var cache = mediaCache ?? []; cache.removeAll { $0.id == upload.id }
        cache.append(MediaCache(id: upload.id, chunks: upload.chunks, cipherBytes: upload.cipherBytes)); mediaCache = cache
    }
    public var liveMediaUploadIDs: Set<String> {
        Set(records.filter {$0.kind == "entry" && !$0.deleted}.flatMap {$0.mediaReferences.map(\.id)})
    }
    public var uploadableRecords: [VaultRecord] {
        // An in-flight deletion/repair must not publish fresh dangling references.
        guard let removals=try? mediaPurgeIntents() else {return []}
        let pending = Set((mediaUploads ?? []).map(\.id)).union(removals.filter{$0.phase != .queued}.map{$0.media.id})
        return records.filter { $0.dirty && ($0.deleted || Set($0.mediaReferences.map(\.id)).isDisjoint(with: pending)) }
    }
}
