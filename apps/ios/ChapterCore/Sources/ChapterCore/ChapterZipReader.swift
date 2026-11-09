// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

/// Reads a ZIP archive the way the web importer's fflate `unzipSync` does (stored and
/// deflated members, ZIP64, UTF-8 or Latin-1 names), one member at a time so a large
/// Day One export can stay memory-mapped. Pure Swift (RFC 1951 inflate), so it behaves
/// the same on iOS and in the Linux test build.
public struct ChapterZipReader {
    public struct Member { public let name: String; let method: UInt16; let offset: Int; let compressed: Int; public let size: Int; let crc: UInt32 }
    public enum ZipError: Error, Equatable { case invalid, unsupported(UInt16), tooLarge, corrupt }
    let data: Data
    /// Members in central-directory order.
    public let members: [Member]

    public init(_ data: Data) throws {
        self.data = data
        func u16(_ o: Int) throws -> Int { guard o >= 0, o + 2 <= data.count else { throw ZipError.invalid }; return Int(data[data.startIndex + o]) | Int(data[data.startIndex + o + 1]) << 8 }
        func u32(_ o: Int) throws -> Int { let lo = try u16(o), hi = try u16(o + 2); return lo | hi << 16 }
        func u64(_ o: Int) throws -> Int { let lo = try u32(o), hi = try u32(o + 4); guard hi < 1 << 20 else { throw ZipError.tooLarge }; return lo | hi << 32 }
        // End of central directory: the last signature within the final 64 KiB + 22 bytes.
        var end = data.count - 22
        let floor = max(0, data.count - 22 - 0xFFFF)
        while end >= floor, (try? u32(end)) != 0x06054b50 { end -= 1 }
        guard end >= floor, end >= 0 else { throw ZipError.invalid }
        var count = try u16(end + 10), at = try u32(end + 16)
        let zip64 = count == 0xFFFF || at == 0xFFFF_FFFF
        if zip64 {
            guard end >= 20, try u32(end - 20) == 0x07064b50 else { throw ZipError.invalid }
            let record = try u64(end - 12)
            guard try u32(record) == 0x06064b50 else { throw ZipError.invalid }
            count = try u64(record + 32); at = try u64(record + 48)
        }
        var members: [Member] = []
        for _ in 0..<count {
            guard try u32(at) == 0x02014b50 else { throw ZipError.invalid }
            let flags = try u16(at + 8), method = UInt16(try u16(at + 10)), crc = UInt32(try u32(at + 16))
            var compressed = try u32(at + 20), size = try u32(at + 24), local = try u32(at + 42)
            let nameLength = try u16(at + 28), extraLength = try u16(at + 30), commentLength = try u16(at + 32)
            guard at + 46 + nameLength <= data.count else { throw ZipError.invalid }
            let nameBytes = data.subdata(in: data.startIndex + at + 46 ..< data.startIndex + at + 46 + nameLength)
            let name = flags & 0x800 != 0 ? String(decoding: nameBytes, as: UTF8.self) : String(String.UnicodeScalarView(nameBytes.map { Unicode.Scalar($0) }))
            // ZIP64 extended information: only the fields that overflowed, in order.
            var e = at + 46 + nameLength; let extraEnd = e + extraLength
            while e + 4 <= extraEnd {
                let id = try u16(e), length = try u16(e + 2)
                if id == 0x0001 {
                    var f = e + 4
                    if size == 0xFFFF_FFFF { size = try u64(f); f += 8 }
                    if compressed == 0xFFFF_FFFF { compressed = try u64(f); f += 8 }
                    if local == 0xFFFF_FFFF { local = try u64(f) }
                }
                e += 4 + length
            }
            guard try u32(local) == 0x04034b50 else { throw ZipError.invalid }
            let nameField = try u16(local + 26), extraField = try u16(local + 28)
            let offset = local + 30 + nameField + extraField
            guard offset + compressed <= data.count else { throw ZipError.invalid }
            members.append(Member(name: name, method: method, offset: offset, compressed: compressed, size: size, crc: crc))
            at += 46 + nameLength + extraLength + commentLength
        }
        self.members = members
    }

    /// One member's bytes (inflated when deflated); refuses more than `limit` bytes.
    public func contents(_ m: Member, limit: Int = 1 << 30) throws -> Data {
        guard m.size <= limit else { throw ZipError.tooLarge }
        let raw = data.subdata(in: data.startIndex + m.offset ..< data.startIndex + m.offset + m.compressed)
        switch m.method {
        case 0: return raw
        case 8: return try Inflate.inflate(raw, expected: m.size, limit: limit)
        default: throw ZipError.unsupported(m.method)
        }
    }

    /// `unzipSync`'s object: later duplicates win, keys keep the first position, and
    /// array-index-like names ("12") come first, ascending, like any JavaScript object.
    public var jsOrderedNames: [String] {
        var seen = Set<String>(), names: [String] = []
        for m in members where seen.insert(m.name).inserted { names.append(m.name) }
        return names.filter(JSValue.isArrayIndex).sorted { UInt64($0)! < UInt64($1)! } + names.filter { !JSValue.isArrayIndex($0) }
    }
    public func last(named name: String) -> Member? { members.last { $0.name == name } }
}

/// RFC 1951 raw DEFLATE decoder.
enum Inflate {
    struct Bits {
        let d: [UInt8]; var pos = 0, bit = 0
        mutating func take(_ n: Int) throws -> Int {
            var v = 0
            for i in 0..<n {
                guard pos < d.count else { throw ChapterZipReader.ZipError.corrupt }
                v |= Int((d[pos] >> UInt8(bit)) & 1) << i
                bit += 1; if bit == 8 { bit = 0; pos += 1 }
            }
            return v
        }
        mutating func align() { if bit != 0 { bit = 0; pos += 1 } }
    }
    struct Huffman {
        var counts = [Int](repeating: 0, count: 16), symbols: [Int]
        init(_ lengths: [Int]) throws {
            symbols = [Int](repeating: 0, count: lengths.count)
            for l in lengths { counts[l] += 1 }
            counts[0] = 0
            var offs = [Int](repeating: 0, count: 16), left = 1
            for len in 1..<16 { left <<= 1; left -= counts[len]; guard left >= 0 else { throw ChapterZipReader.ZipError.corrupt } }
            for len in 1..<15 { offs[len + 1] = offs[len] + counts[len] }
            for (s, l) in lengths.enumerated() where l != 0 { symbols[offs[l]] = s; offs[l] += 1 }
        }
        func decode(_ b: inout Bits) throws -> Int {
            var code = 0, first = 0, index = 0
            for len in 1..<16 {
                code |= try b.take(1)
                let count = counts[len]
                if code - count < first { return symbols[index + (code - first)] }
                index += count; first += count; first <<= 1; code <<= 1
            }
            throw ChapterZipReader.ZipError.corrupt
        }
    }
    static let lengthBase = [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258]
    static let lengthExtra = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0]
    static let distBase = [1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577]
    static let distExtra = [0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13]
    static let fixed: (Huffman, Huffman) = {
        var l = [Int](repeating: 8, count: 288)
        for i in 144..<256 { l[i] = 9 }; for i in 256..<280 { l[i] = 7 }
        return (try! Huffman(l), try! Huffman([Int](repeating: 5, count: 30)))
    }()

    static func inflate(_ input: Data, expected: Int, limit: Int) throws -> Data {
        var b = Bits(d: [UInt8](input)), out = [UInt8](); out.reserveCapacity(min(expected, limit))
        var final = 0
        repeat {
            final = try b.take(1)
            switch try b.take(2) {
            case 0:
                b.align()
                guard b.pos + 4 <= b.d.count else { throw ChapterZipReader.ZipError.corrupt }
                let len = Int(b.d[b.pos]) | Int(b.d[b.pos + 1]) << 8, nlen = Int(b.d[b.pos + 2]) | Int(b.d[b.pos + 3]) << 8
                guard len == ~nlen & 0xFFFF, b.pos + 4 + len <= b.d.count, out.count + len <= limit else { throw ChapterZipReader.ZipError.corrupt }
                out.append(contentsOf: b.d[(b.pos + 4)..<(b.pos + 4 + len)]); b.pos += 4 + len
            case 1: try codes(&b, &out, fixed.0, fixed.1, limit)
            case 2:
                let hlit = try b.take(5) + 257, hdist = try b.take(5) + 1, hclen = try b.take(4) + 4
                let order = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]
                var cl = [Int](repeating: 0, count: 19)
                for i in 0..<hclen { cl[order[i]] = try b.take(3) }
                let clh = try Huffman(cl)
                var lengths: [Int] = []
                while lengths.count < hlit + hdist {
                    let sym = try clh.decode(&b)
                    switch sym {
                    case 0..<16: lengths.append(sym)
                    case 16: guard let prev = lengths.last else { throw ChapterZipReader.ZipError.corrupt }; lengths += [Int](repeating: prev, count: try 3 + b.take(2))
                    case 17: lengths += [Int](repeating: 0, count: try 3 + b.take(3))
                    default: lengths += [Int](repeating: 0, count: try 11 + b.take(7))
                    }
                }
                guard lengths.count == hlit + hdist, lengths[256] != 0 else { throw ChapterZipReader.ZipError.corrupt }
                try codes(&b, &out, try Huffman(Array(lengths[0..<hlit])), try Huffman(Array(lengths[hlit...])), limit)
            default: throw ChapterZipReader.ZipError.corrupt
            }
        } while final == 0
        guard out.count == expected else { throw ChapterZipReader.ZipError.corrupt }
        return Data(out)
    }
    static func codes(_ b: inout Bits, _ out: inout [UInt8], _ lit: Huffman, _ dist: Huffman, _ limit: Int) throws {
        while true {
            let sym = try lit.decode(&b)
            if sym < 256 { guard out.count < limit else { throw ChapterZipReader.ZipError.tooLarge }; out.append(UInt8(sym)); continue }
            if sym == 256 { return }
            let li = sym - 257
            guard li < 29 else { throw ChapterZipReader.ZipError.corrupt }
            let length = try lengthBase[li] + b.take(lengthExtra[li])
            let di = try dist.decode(&b)
            guard di < 30 else { throw ChapterZipReader.ZipError.corrupt }
            let distance = try distBase[di] + b.take(distExtra[di])
            guard distance <= out.count, out.count + length <= limit else { throw ChapterZipReader.ZipError.corrupt }
            let start = out.count - distance
            for k in 0..<length { out.append(out[start + k]) }
        }
    }
}
