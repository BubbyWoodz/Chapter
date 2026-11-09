// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

/// Local navigation ONLY. An entry ID never becomes a server URL or external host.
public enum EntryLinkRoute {
    public static func url(for id:String)->URL? {
        guard !id.isEmpty,id.utf8.count<=512,!id.unicodeScalars.contains(where:{CharacterSet.controlCharacters.contains($0)}) else {return nil}
        var parts=URLComponents();parts.scheme="chapter-entry";parts.host="open";parts.queryItems=[URLQueryItem(name:"id",value:id)];return parts.url
    }
    public static func entryID(from url:URL)->String? {
        guard let parts=URLComponents(url:url,resolvingAgainstBaseURL:false),parts.scheme=="chapter-entry",parts.host=="open",parts.user==nil,parts.password==nil,parts.port==nil,parts.path.isEmpty,parts.fragment==nil,
              let query=parts.queryItems,query.count==1,query[0].name=="id",let id=query[0].value,Self.url(for:id) != nil else {return nil}
        return id
    }
}
public extension VaultRecord {
    /// Match actual upstream docEntryLinks: document order and duplicates retained,
    /// including content under an otherwise opaque node; never rewrite the tree.
    var linkedEntryIDs:[String] {
        guard let raw=body["bodyJson"]?.string,raw.utf8.count<=8*1024*1024,let root=try? JSONDecoder().decode(JSONValue.self,from:Data(raw.utf8)) else {return []}
        var ids:[String]=[],count=0
        func walk(_ node:JSONValue,_ depth:Int) throws {
            count+=1;guard depth<128,count<=100_000,case .object=node else {throw ChapterError.unsupported}
            if node["type"].string=="entryLink",let id=node["attrs"]["entryId"].string,!id.isEmpty {ids.append(id)}
            if case .null=node["content"] {return}
            guard case .array(let children)=node["content"] else {throw ChapterError.corruptData}
            for child in children {try walk(child,depth+1)}
        }
        do {try walk(root,0);return ids} catch {return []}
    }
    var uniqueLinkedEntryIDs:[String] {
        var seen=Set<Data>();return linkedEntryIDs.filter{seen.insert(Data($0.utf8)).inserted}
    }
}
public extension VaultSnapshot {
    /// Mirrors original Editor backlinks, scoped honestly to downloaded entries.
    func backlinks(to id:String)->[VaultRecord] {
        records.filter{$0.kind=="entry" && !$0.deleted && !Data($0.id.utf8).elementsEqual(id.utf8) && $0.linkedEntryIDs.contains(where:{$0.utf8.elementsEqual(id.utf8)})}.sorted {
            let a=$0.body["updatedAt"]?.number ?? Double($0.clock),b=$1.body["updatedAt"]?.number ?? Double($1.clock)
            return (a.isFinite ? a:0)>(b.isFinite ? b:0)
        }
    }
}
