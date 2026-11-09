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

// MARK: - Authoring (mirrors original web wikilink.ts buildEntryLinkItems/insertEntryLink)

public enum EntryLinkAuthoring {
    /// Web `e.title || t('common.untitled')`: only an empty/missing title falls back.
    public static func label(for target:VaultRecord)->String {
        if let title=target.body["title"]?.string,!title.isEmpty {return title}
        return "Untitled"
    }
    /// ECMAScript String.prototype.trim whitespace (same set as the preview trim).
    static let ecmaWhitespace=CharacterSet(charactersIn:"\u{0009}\u{000A}\u{000B}\u{000C}\u{000D}\u{0020}\u{00A0}\u{1680}\u{2000}\u{2001}\u{2002}\u{2003}\u{2004}\u{2005}\u{2006}\u{2007}\u{2008}\u{2009}\u{200A}\u{2028}\u{2029}\u{202F}\u{205F}\u{3000}\u{FEFF}")
    /// JS `includes` compares UTF-16 code units, never canonical equivalence.
    static func utf16Contains(_ haystack:String,_ needle:String)->Bool {
        let h=Array(haystack.utf16),n=Array(needle.utf16)
        if n.isEmpty {return true}; guard n.count<=h.count else {return false}
        for start in 0...(h.count-n.count) where h[start..<(start+n.count)].elementsEqual(n) {return true}
        return false
    }
    static func updatedAt(_ record:VaultRecord)->Double {
        let value=record.body["updatedAt"]?.number ?? Double(record.clock); return value.isFinite ? value:0
    }
}
public extension VaultSnapshot {
    /// Other live downloaded entries matching the query, most recently touched first, at most 8.
    func entryLinkCandidates(excluding currentID:String,query:String)->[VaultRecord] {
        let q=query.trimmingCharacters(in:EntryLinkAuthoring.ecmaWhitespace).lowercased()
        let matches=records.enumerated().filter {
            $0.element.kind=="entry" && !$0.element.deleted && !Data($0.element.id.utf8).elementsEqual(currentID.utf8)
                && (q.isEmpty || EntryLinkAuthoring.utf16Contains(EntryLinkAuthoring.label(for:$0.element).lowercased(),q))
        }
        // Stable like Array.prototype.sort: equal timestamps keep original order.
        return matches.sorted {
            let a=EntryLinkAuthoring.updatedAt($0.element),b=EntryLinkAuthoring.updatedAt($1.element)
            return a != b ? a>b : $0.offset<$1.offset
        }.prefix(8).map(\.element)
    }
}
public extension RichDocument {
    /// Appends a paragraph holding exactly what the web editor inserts:
    /// `{type:entryLink,attrs:{entryId,label}}` followed by a `" "` text node.
    mutating func appendEntryLink(entryID:String,label:String) throws {
        guard EntryLinkRoute.url(for:entryID) != nil,label.utf8.count<=64*1024,case .object(var fields)=root else {throw ChapterError.unsupported}
        let link:JSONValue = .object(["type":.string("entryLink"),"attrs":.object(["entryId":.string(entryID),"label":.string(label)])])
        let space:JSONValue = .object(["type":.string("text"),"text":.string(" ")])
        var children=fields["content"]?.array ?? []
        children.append(.object(["type":.string("paragraph"),"content":.array([link,space])]))
        fields["content"] = .array(children)
        self=try RichDocument(json:String(decoding:JSONEncoder().encode(JSONValue.object(fields)),as:UTF8.self))
    }
}
public extension VaultRecord {
    /// Compare-and-set on the exact original document bytes; refuses self,
    /// deleted, non-entry and missing targets without mutating anything.
    func addingEntryLink(to target:VaultRecord,expected:String,now:Date=Date()) throws -> VaultRecord {
        guard target.kind=="entry",!target.deleted,!Data(target.id.utf8).elementsEqual(id.utf8) else {throw ChapterError.unsupported}
        return try editingRichDocument(expected:expected,now:now) {try $0.appendEntryLink(entryID:target.id,label:EntryLinkAuthoring.label(for:target))}
    }
}
