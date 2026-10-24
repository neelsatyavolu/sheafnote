import Foundation

/// Reads a store-only ZIP (the kind `ZipWriter` produces). The central directory is parsed up front; entry bytes are
/// read on demand and checked against their CRC-32. Compressed entries are rejected with a typed error.
public struct ZipReader {
    public struct Entry: Equatable, Sendable {
        public let name: String
        public let size: Int
        let crc: UInt32
        let method: UInt16
        let localOffset: UInt64
    }

    public let entries: [Entry]
    private let data: Data
    private let index: [String: Entry]

    public init(url: URL) throws {
        let mapped: Data
        do { mapped = try Data(contentsOf: url, options: .alwaysMapped) } catch {
            throw ArchiveError.ioFailure(error.localizedDescription)
        }
        try self.init(data: mapped)
    }

    public init(data: Data) throws {
        self.data = data
        let directory = try Self.locateDirectory(in: data)
        var parsed: [Entry] = []
        var cursor = Int(directory.offset)
        for _ in 0..<directory.count {
            let (entry, next) = try Self.parseEntry(in: data, at: cursor, limit: Int(directory.offset + directory.size))
            parsed.append(entry)
            cursor = next
        }
        var byName: [String: Entry] = [:]
        for entry in parsed {
            try ZipNames.validate(entry.name)
            guard byName.updateValue(entry, forKey: entry.name) == nil else { throw ArchiveError.duplicateEntry(entry.name) }
        }
        entries = parsed
        index = byName
    }

    public func contains(_ name: String) -> Bool { index[name] != nil }

    public func read(_ name: String) throws -> Data {
        guard let entry = index[name] else { throw ArchiveError.missingEntry(name) }
        guard entry.method == 0 else { throw ArchiveError.unsupportedCompression(name) }
        let local = Int(clamping: entry.localOffset)
        guard local >= 0, local + 30 <= data.count, Self.u32(data, local) == 0x0403_4B50 else {
            throw ArchiveError.corrupt("entry \(name) points outside the file")
        }
        let start = local + 30 + Int(Self.u16(data, local + 26)) + Int(Self.u16(data, local + 28))
        let end = start + entry.size
        guard start >= 0, end >= start, end <= data.count else { throw ArchiveError.truncated }
        let bytes = data.subdata(in: (data.startIndex + start)..<(data.startIndex + end))
        guard CRC32.checksum(of: bytes) == entry.crc else { throw ArchiveError.corrupt("checksum mismatch in \(name)") }
        return bytes
    }

    // MARK: Parsing

    private struct Directory { var count: Int; var size: UInt64; var offset: UInt64 }

    private static func locateDirectory(in data: Data) throws -> Directory {
        guard data.count >= 22 else { throw data.isEmpty ? ArchiveError.notAnArchive : ArchiveError.truncated }
        let lowest = max(0, data.count - 22 - 65_535)
        var position = data.count - 22
        while position >= lowest {
            if u32(data, position) == 0x0605_4B50 { return try directory(in: data, endRecordAt: position) }
            position -= 1
        }
        throw data.starts(with: [0x50, 0x4B]) ? ArchiveError.truncated : ArchiveError.notAnArchive
    }

    private static func directory(in data: Data, endRecordAt end: Int) throws -> Directory {
        var count = UInt64(u16(data, end + 10))
        var size = UInt64(u32(data, end + 12))
        var offset = UInt64(u32(data, end + 16))
        if (count == 0xFFFF || size == 0xFFFF_FFFF || offset == 0xFFFF_FFFF), end >= 20,
           u32(data, end - 20) == 0x0706_4B50 {
            let zip64End = Int(clamping: u64(data, end - 20 + 8))
            guard zip64End >= 0, zip64End + 56 <= data.count, u32(data, zip64End) == 0x0606_4B50 else {
                throw ArchiveError.corrupt("bad ZIP64 directory")
            }
            count = u64(data, zip64End + 32)
            size = u64(data, zip64End + 40)
            offset = u64(data, zip64End + 48)
        }
        guard offset <= UInt64(data.count), size <= UInt64(data.count) - offset, count <= UInt64(data.count) / 46 + 1
        else { throw ArchiveError.truncated }
        return Directory(count: Int(count), size: size, offset: offset)
    }

    private static func parseEntry(in data: Data, at p: Int, limit: Int) throws -> (Entry, Int) {
        guard p + 46 <= limit, u32(data, p) == 0x0201_4B50 else { throw ArchiveError.corrupt("bad directory entry") }
        let method = u16(data, p + 10)
        let crc = u32(data, p + 16)
        var compressed = UInt64(u32(data, p + 20))
        var size = UInt64(u32(data, p + 24))
        let nameLength = Int(u16(data, p + 28)), extraLength = Int(u16(data, p + 30)), commentLength = Int(u16(data, p + 32))
        var offset = UInt64(u32(data, p + 42))
        let next = p + 46 + nameLength + extraLength + commentLength
        guard next <= limit else { throw ArchiveError.corrupt("bad directory entry") }
        let nameStart = data.startIndex + p + 46
        guard let name = String(data: data.subdata(in: nameStart..<(nameStart + nameLength)), encoding: .utf8) else {
            throw ArchiveError.corrupt("file name is not UTF-8")
        }
        if size == 0xFFFF_FFFF || compressed == 0xFFFF_FFFF || offset == 0xFFFF_FFFF {
            var q = p + 46 + nameLength
            let extraEnd = q + extraLength
            while q + 4 <= extraEnd {
                let id = u16(data, q), length = Int(u16(data, q + 2))
                if id == 1 {
                    var r = q + 4
                    if size == 0xFFFF_FFFF, r + 8 <= extraEnd { size = u64(data, r); r += 8 }
                    if compressed == 0xFFFF_FFFF, r + 8 <= extraEnd { compressed = u64(data, r); r += 8 }
                    if offset == 0xFFFF_FFFF, r + 8 <= extraEnd { offset = u64(data, r) }
                }
                q += 4 + length
            }
        }
        guard size <= UInt64(Int32.max) * 1024, size == compressed || method != 0 else {
            throw ArchiveError.corrupt("entry \(name) has inconsistent sizes")
        }
        return (Entry(name: name, size: Int(clamping: size), crc: crc, method: method, localOffset: offset), next)
    }

    private static func u16(_ d: Data, _ p: Int) -> UInt16 {
        let i = d.startIndex + p
        return UInt16(d[i]) | UInt16(d[i + 1]) << 8
    }

    private static func u32(_ d: Data, _ p: Int) -> UInt32 { UInt32(u16(d, p)) | UInt32(u16(d, p + 2)) << 16 }
    private static func u64(_ d: Data, _ p: Int) -> UInt64 { UInt64(u32(d, p)) | UInt64(u32(d, p + 4)) << 32 }
}
