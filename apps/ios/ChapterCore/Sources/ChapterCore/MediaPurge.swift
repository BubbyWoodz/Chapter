// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

/// Local encrypted intent, never a synced record. Stored in the existing opaque
/// recovery array so older clients retain it without understanding or executing it.
/// These transitions are NOT permission to issue DELETE before saving the intent.
public struct MediaPurgeIntent: Codable, Equatable, Identifiable {
    public static let recoveryKind = "chapterLocalMediaPurge"
    public enum Phase: String, Codable { case queued, sending, confirmed }
    public let id: String
    public let media: MediaCache
    public let revision: Int64
    public let phase: Phase
    init(media: MediaCache) { id="local-media-purge-"+UUID().uuidString.lowercased();self.media=media;revision=1;phase = .queued }
    private init(id:String,media:MediaCache,revision:Int64,phase:Phase) {self.id=id;self.media=media;self.revision=revision;self.phase=phase}
    func advanced(to phase: Phase) throws -> Self {
        Self(id:id,media:media,revision:try ProtocolNumbers.nextClock(after:revision,now:Date(timeIntervalSince1970:0)),phase:phase)
    }
    func validate() throws {
        guard id.hasPrefix("local-media-purge-"),MediaLimits.validID(id),revision>0 else {throw ChapterError.corruptData}
        try ProtocolNumbers.validate(revision);try media.validatePurgeMetadata()
    }
    public func recoveryRecord() throws -> VaultRecord {
        try validate()
        let payload=try JSONDecoder().decode(JSONValue.self,from:JSONEncoder().encode(self))
        return VaultRecord(id:id,clock:revision,body:["kind":.string(Self.recoveryKind),"title":.string("Attachment removal"),"localMediaPurge":payload])
    }
    public init(recovery: VaultRecord) throws {
        guard recovery.kind==Self.recoveryKind,let payload=recovery.body["localMediaPurge"] else {throw ChapterError.corruptData}
        self=try JSONDecoder().decode(Self.self,from:JSONEncoder().encode(payload));try validate()
        guard try recoveryRecord()==recovery else {throw ChapterError.corruptData}
    }
}
public struct MediaPurgeReview {
    public let media: MediaCache
    fileprivate let checkpoint: Data
}
private func purgeEncoding<T:Encodable>(_ value:T) throws -> Data {
    let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys];return try encoder.encode(value)
}
private extension MediaCache {
    func validatePurgeMetadata() throws {
        guard MediaLimits.validID(id),(1...128).contains(chunks),cipherBytes>=Int64(chunks*41),
              cipherBytes<=Int64(MediaLimits.maximumPlainBytes+chunks*41) else {throw ChapterError.corruptData}
        let plain=Int(cipherBytes-Int64(chunks*41))
        guard chunks==max(1,(plain+MediaLimits.chunkBytes-1)/MediaLimits.chunkBytes) else {throw ChapterError.corruptData}
    }
}
public extension VaultSnapshot {
    /// Malformed intents fail closed instead of disappearing from the queue.
    func mediaPurgeIntents() throws -> [MediaPurgeIntent] {
        let intents=try conflicts.filter{$0.kind==MediaPurgeIntent.recoveryKind}.map{try MediaPurgeIntent(recovery:$0)}
        guard Set(intents.map(\.id)).count==intents.count,Set(intents.map{$0.media.id}).count==intents.count else {throw ChapterError.corruptData}
        return intents
    }
    /// Conservative local guard. This does NOT inspect unsynced other devices or
    /// provide an atomic remote reference fence in the original server protocol.
    /// Include tombstones/recoveries and opaque attrs, not just rendered media nodes.
    func requireMediaPurgeUnreferenced(_ media:MediaCache) throws {
        try media.validatePurgeMetadata()
        guard (mediaCache ?? []).filter({$0.id==media.id}) == [media],
              !(mediaUploads ?? []).contains(where:{$0.id==media.id}),
              (richDrafts ?? []).isEmpty,!records.contains(where:{$0.dirty}) else {throw ChapterError.conflict}
        _ = try mediaPurgeIntents()
        let allowedBody:Set<String>=["kind","journalId","title","name","subtitle","color","cover","createdAt","updatedAt","bodyText","bodyJson","labels","attachments","chapterNativePlain","archived","order","appearance"]
        let allowedNodes=RichDocument.containers.union(["text","hardBreak","horizontalRule","mediaAttachment","mediaGallery","locationMap","videoInterview"])
        let allowedMarks:Set<String>=["bold","italic","underline","strike","code","link","highlight","textStyle","subscript","superscript"]
        var visited=0
        func inspect(_ value:JSONValue,_ depth:Int=0) throws {
            visited+=1;guard depth<64,visited<=200_000 else {throw ChapterError.unsupported}
            switch value {
            case .string(let text):
                guard !text.contains(media.id) else {throw ChapterError.conflict}
                // Also catch escaped IDs within encoded rich JSON / opaque JSON strings.
                if text.utf8.count<=8*1024*1024,let decoded=try? JSONDecoder().decode(JSONValue.self,from:Data(text.utf8)) {try inspect(decoded,depth+1)}
            case .array(let values):for child in values {try inspect(child,depth+1)}
            case .object(let fields):
                for (key,child) in fields {guard !key.contains(media.id) else {throw ChapterError.conflict};try inspect(child,depth+1)}
            case .number(let number):guard number.isFinite else {throw ChapterError.corruptData}
            default:break
            }
        }
        func inspectKnownAttributes(_ value:JSONValue,_ depth:Int=0) throws {
            guard depth<64 else {throw ChapterError.unsupported}
            let keys:Set<String>=["level","checked","language","start","colspan","rowspan","colwidth","textAlign","id","kind","mime","name","bytes","caption","width","height","images","map","photo","cards","clip","film","question","questionId","answer","duration","recordedAt","lat","lng","zoom","href","target","rel","class","color"]
            switch value {
            case .object(let fields):guard Set(fields.keys).isSubset(of:keys) else {throw ChapterError.unsupported};for child in fields.values {try inspectKnownAttributes(child,depth+1)}
            case .array(let values):for child in values {try inspectKnownAttributes(child,depth+1)}
            default:break
            }
        }
        func inspectNode(_ value:JSONValue,_ depth:Int=0) throws {
            guard depth<64,let type=value["type"].string,allowedNodes.contains(type),case .object(let fields)=value,
                  Set(fields.keys).isSubset(of:["type","attrs","content","text","marks"]) else {throw ChapterError.unsupported}
            // Unknown attributes can encode future media relationships. Refuse,
            // never infer absence just because the native reader cannot render it.
            try inspectKnownAttributes(value["attrs"])
            for mark in value["marks"].array {
                guard allowedMarks.contains(mark["type"].string ?? ""),case .object(let fields)=mark,Set(fields.keys).isSubset(of:["type","attrs"]) else {throw ChapterError.unsupported}
                try inspectKnownAttributes(mark["attrs"])
            }
            for child in value["content"].array {try inspectNode(child,depth+1)}
        }
        for record in records+conflicts.filter({$0.kind != MediaPurgeIntent.recoveryKind}) {
            // A failed writing draft may hold an expected entry/media checkpoint.
            // Keep every such recovery intact, even if the target ID is not visible.
            guard ["entry","journal","aiSettings"].contains(record.kind),Set(record.body.keys).isSubset(of:allowedBody) else {throw ChapterError.unsupported}
            try inspect(.object(record.body))
            if let value=record.body["bodyJson"],value != .null {
                guard let raw=value.string else {throw ChapterError.unsupported}
                let document=try RichDocument(json:raw);try inspectNode(document.root)
            }
            if let attachments=record.body["attachments"],attachments != .null {
                guard case .array=attachments else {throw ChapterError.unsupported};try inspectKnownAttributes(attachments)
            }
        }
    }
    func reviewMediaPurge(_ media:MediaCache) throws -> MediaPurgeReview {
        try requireMediaPurgeUnreferenced(media)
        guard !(try mediaPurgeIntents()).contains(where:{$0.media.id==media.id}) else {throw ChapterError.conflict}
        return MediaPurgeReview(media:media,checkpoint:try purgeEncoding(self))
    }
    @discardableResult mutating func queueMediaPurge(_ review:MediaPurgeReview) throws -> MediaPurgeIntent {
        guard try purgeEncoding(self)==review.checkpoint else {throw ChapterError.conflict}
        _ = try reviewMediaPurge(review.media)
        let intent=MediaPurgeIntent(media:review.media);conflicts.append(try intent.recoveryRecord());return intent
    }
    private func purgeIndex(_ expected:MediaPurgeIntent) throws -> Int {
        let record=try expected.recoveryRecord()
        guard let index=conflicts.firstIndex(where:{$0.id==expected.id}),conflicts[index]==record else {throw ChapterError.conflict}
        return index
    }
    /// Save returned .sending state BEFORE HTTP; after this point cancellation
    /// cannot claim the server has not seen the request. Restart retries DELETE.
    @discardableResult mutating func beginMediaPurge(_ expected:MediaPurgeIntent) throws -> MediaPurgeIntent {
        let index=try purgeIndex(expected);guard expected.phase != .confirmed else {throw ChapterError.conflict}
        try requireMediaPurgeUnreferenced(expected.media)
        let next=try expected.advanced(to:.sending);conflicts[index]=try next.recoveryRecord();return next
    }
    /// Call ONLY after strict authenticated204, and persist before local cleanup.
    @discardableResult mutating func confirmMediaPurge(_ expected:MediaPurgeIntent) throws -> MediaPurgeIntent {
        let index=try purgeIndex(expected);guard expected.phase == .sending else {throw ChapterError.conflict}
        try requireMediaPurgeUnreferenced(expected.media)
        let next=try expected.advanced(to:.confirmed);conflicts[index]=try next.recoveryRecord();return next
    }
    /// File cleanup and this acknowledgement must follow durable .confirmed.
    /// Recheck immediately before physical cleanup; never clear referenced work.
    mutating func finishMediaPurge(_ expected:MediaPurgeIntent) throws {
        let index=try purgeIndex(expected);guard expected.phase == .confirmed else {throw ChapterError.conflict}
        try requireMediaPurgeUnreferenced(expected.media)
        mediaCache=mediaCache?.filter{$0.id != expected.media.id};conflicts.remove(at:index)
    }
    mutating func cancelMediaPurge(_ expected:MediaPurgeIntent) throws {
        let index=try purgeIndex(expected);guard expected.phase == .queued else {throw ChapterError.conflict}
        conflicts.remove(at:index)
    }
}
