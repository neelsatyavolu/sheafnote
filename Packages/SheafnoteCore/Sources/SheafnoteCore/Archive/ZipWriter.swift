import Foundation

/// Where a `ZipWriter` sends its bytes.
protocol ZipOutput: AnyObject {
    func write(_ data: Data) throws
}

final class MemoryZipOutput: ZipOutput {
    private(set) var data = Data()
    func write(_ chunk: Data) throws { data.append(chunk) }
}

final class FileZipOutput: ZipOutput {
    private let handle: FileHandle

    init(url: URL) throws {
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
            throw ArchiveError.ioFailure("could not create \(url.lastPathComponent)")
        }
        handle = try FileHandle(forWritingTo: url)
    }

    func write(_ data: Data) throws {
        do { try handle.write(contentsOf: data) } catch { throw ArchiveError.ioFailure(error.localizedDescription) }
    }

    func close() throws {
        do { try handle.close() } catch { throw ArchiveError.ioFailure(error.localizedDescription) }
    }
}

/// Writes a store-only (no compression) ZIP, streaming one entry at a time.
///
/// Output is deterministic: entries keep the order they were added in, timestamps are fixed at 1980-01-01 and no
/// platform attributes are stored. ZIP64 records are written automatically when an entry, the central directory
/// or the entry count outgrows the classic limits (or always, with `forceZip64`, which the tests use).
public final class ZipWriter {
    static let classicMax: UInt64 = 0xFFFF_FFFF
    static let maxClassicEntries = 0xFFFE
    static let dosDate: UInt16 = (0 << 9) | (1 << 5) | 1   // 1980-01-01

    struct Record {
        let name: [UInt8]
        let crc: UInt32
        let size: UInt64
        let offset: UInt64
        let zip64: Bool
    }

    private let output: any ZipOutput
    private let forceZip64: Bool
    private var records: [Record] = []
    private var names = Set<String>()
    private var position: UInt64 = 0
    private var finished = false

    init(output: any ZipOutput, forceZip64: Bool) {
        self.output = output
        self.forceZip64 = forceZip64
    }

    /// Streams to a new file at `url` (an existing file is replaced by the caller, not here).
    public convenience init(url: URL, forceZip64: Bool = false) throws {
        try self.init(output: FileZipOutput(url: url), forceZip64: forceZip64)
    }

    static func inMemory(forceZip64: Bool = false) -> ZipWriter {
        ZipWriter(output: MemoryZipOutput(), forceZip64: forceZip64)
    }

    // MARK: Entries

    public func add(name: String, data: Data) throws {
        guard !finished else { throw ArchiveError.ioFailure("the archive is already finished") }
        try ZipNames.validate(name)
        guard names.insert(name).inserted else { throw ArchiveError.duplicateEntry(name) }
        let nameBytes = Array(name.utf8)
        let size = UInt64(data.count)
        let zip64 = forceZip64 || size >= Self.classicMax || position >= Self.classicMax
        let record = Record(name: nameBytes, crc: CRC32.checksum(of: data), size: size, offset: position, zip64: zip64)
        try emit(localHeader(for: record))
        try emit(data)
        records.append(record)
    }

    /// Writes the central directory and closes the output.
    public func finish() throws {
        try writeDirectory()
        if let file = output as? FileZipOutput { try file.close() }
    }

    func finishInMemory() throws -> Data {
        try writeDirectory()
        return (output as? MemoryZipOutput)?.data ?? Data()
    }

    // MARK: Layout

    private func emit(_ data: Data) throws {
        try output.write(data)
        position += UInt64(data.count)
    }

    private func localHeader(for r: Record) -> Data {
        var b = ByteBuilder()
        b.u32(0x0403_4B50)
        b.u16(r.zip64 ? 45 : 20)
        b.u16(0x0800)                       // UTF-8 names
        b.u16(0)                            // stored
        b.u16(0); b.u16(Self.dosDate)
        b.u32(r.crc)
        b.u32(r.zip64 ? UInt32.max : UInt32(r.size))
        b.u32(r.zip64 ? UInt32.max : UInt32(r.size))
        b.u16(UInt16(r.name.count))
        b.u16(r.zip64 ? 20 : 0)
        b.bytes(r.name)
        if r.zip64 { b.u16(1); b.u16(16); b.u64(r.size); b.u64(r.size) }
        return b.data
    }

    private func centralEntry(for r: Record) -> Data {
        var b = ByteBuilder()
        b.u32(0x0201_4B50)
        b.u16(r.zip64 ? 45 : 20); b.u16(r.zip64 ? 45 : 20)
        b.u16(0x0800); b.u16(0)
        b.u16(0); b.u16(Self.dosDate)
        b.u32(r.crc)
        b.u32(r.zip64 ? UInt32.max : UInt32(r.size))
        b.u32(r.zip64 ? UInt32.max : UInt32(r.size))
        b.u16(UInt16(r.name.count))
        b.u16(r.zip64 ? 28 : 0)
        b.u16(0); b.u16(0); b.u16(0); b.u32(0)
        b.u32(r.zip64 ? UInt32.max : UInt32(r.offset))
        b.bytes(r.name)
        if r.zip64 { b.u16(1); b.u16(24); b.u64(r.size); b.u64(r.size); b.u64(r.offset) }
        return b.data
    }

    private func writeDirectory() throws {
        guard !finished else { return }
        finished = true
        let directoryStart = position
        for record in records { try emit(centralEntry(for: record)) }
        let directorySize = position - directoryStart
        let needsZip64 = forceZip64 || records.count > Self.maxClassicEntries
            || directoryStart >= Self.classicMax || directorySize >= Self.classicMax
        var b = ByteBuilder()
        if needsZip64 {
            let zip64End = position
            b.u32(0x0606_4B50); b.u64(44); b.u16(45); b.u16(45); b.u32(0); b.u32(0)
            b.u64(UInt64(records.count)); b.u64(UInt64(records.count)); b.u64(directorySize); b.u64(directoryStart)
            b.u32(0x0706_4B50); b.u32(0); b.u64(zip64End); b.u32(1)
        }
        b.u32(0x0605_4B50); b.u16(0); b.u16(0)
        let count = needsZip64 ? UInt16.max : UInt16(records.count)
        b.u16(count); b.u16(count)
        b.u32(needsZip64 ? UInt32.max : UInt32(directorySize))
        b.u32(needsZip64 ? UInt32.max : UInt32(directoryStart))
        b.u16(0)
        try emit(b.data)
    }
}

enum ZipNames {
    /// Entry names are relative, `/`-separated, with no empty or `..` components, backslashes or NULs.
    static func validate(_ name: String) throws {
        let bad = name.isEmpty || name.hasPrefix("/") || name.hasSuffix("/") || name.contains("\\") || name.contains("\0")
            || name.utf8.count > Int(UInt16.max)
        guard !bad else { throw ArchiveError.invalidEntryName(name) }
        for part in name.split(separator: "/", omittingEmptySubsequences: false) {
            if part.isEmpty || part == ".." || part == "." { throw ArchiveError.invalidEntryName(name) }
        }
    }
}

struct ByteBuilder {
    private(set) var data = Data()

    mutating func u16(_ v: UInt16) { data.append(contentsOf: [UInt8(v & 0xFF), UInt8(v >> 8)]) }
    mutating func u32(_ v: UInt32) { u16(UInt16(v & 0xFFFF)); u16(UInt16(v >> 16)) }
    mutating func u64(_ v: UInt64) { u32(UInt32(v & 0xFFFF_FFFF)); u32(UInt32(v >> 32)) }
    mutating func bytes(_ b: [UInt8]) { data.append(contentsOf: b) }
}
