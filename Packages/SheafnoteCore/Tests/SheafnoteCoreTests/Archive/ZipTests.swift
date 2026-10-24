import Foundation
import Testing
@testable import SheafnoteCore

@Suite("Store-only ZIP")
struct ZipTests {
    private func sampleEntries() -> [(String, Data)] {
        [("manifest.json", Data("{\"a\":1}".utf8)),
         ("ink/page-1.drawing", Data((0..<5000).map { UInt8($0 % 251) })),
         ("assets/empty", Data()),
         ("dir/ünïcode name.txt", Data("héllo".utf8))]
    }

    private func write(_ entries: [(String, Data)], zip64: Bool = false) throws -> Data {
        let writer = ZipWriter.inMemory(forceZip64: zip64)
        for (name, data) in entries { try writer.add(name: name, data: data) }
        return try writer.finishInMemory()
    }

    @Test func crc32MatchesTheStandardCheckValue() {
        #expect(CRC32.checksum(of: Data("123456789".utf8)) == 0xCBF4_3926)
        #expect(CRC32.checksum(of: Data()) == 0)
    }

    @Test func crc32IsIncrementalAndConsistent() {
        let data = Data((0..<10_000).map { UInt8($0 % 256) })
        var crc = CRC32()
        crc.update(data.prefix(3333))
        crc.update(data.dropFirst(3333))
        #expect(crc.value == CRC32.checksum(of: data))
    }

    @Test func roundTripsEntriesInOrder() throws {
        let entries = sampleEntries()
        let reader = try ZipReader(data: try write(entries))
        #expect(reader.entries.map(\.name) == entries.map(\.0))
        for (name, data) in entries { #expect(try reader.read(name) == data) }
        #expect(reader.contains("manifest.json"))
        #expect(!reader.contains("nope"))
    }

    @Test func outputIsDeterministic() throws {
        #expect(try write(sampleEntries()) == write(sampleEntries()))
    }

    @Test func zip64RoundTrips() throws {
        let entries = sampleEntries()
        let bytes = try write(entries, zip64: true)
        let reader = try ZipReader(data: bytes)
        #expect(reader.entries.count == entries.count)
        for (name, data) in entries { #expect(try reader.read(name) == data) }
    }

    @Test func emptyArchiveIsValid() throws {
        let reader = try ZipReader(data: try write([]))
        #expect(reader.entries.isEmpty)
    }

    @Test func rejectsUnsafeAndDuplicateNames() throws {
        let writer = ZipWriter.inMemory()
        for bad in ["", "/abs", "../up", "a/../b", "a\\b", "a\0b", "dir//x", "trailing/"] {
            #expect(throws: ArchiveError.self) { try writer.add(name: bad, data: Data()) }
        }
        try writer.add(name: "ok", data: Data())
        #expect(throws: ArchiveError.self) { try writer.add(name: "ok", data: Data()) }
    }

    @Test func detectsACorruptedEntry() throws {
        var bytes = try write([("a.bin", Data(repeating: 7, count: 100))])
        bytes[40] ^= 0xFF   // inside the stored data of the only entry
        let reader = try ZipReader(data: bytes)
        #expect(throws: ArchiveError.self) { try reader.read("a.bin") }
    }

    @Test func rejectsTruncatedAndGarbageInput() throws {
        let bytes = try write(sampleEntries())
        #expect(throws: ArchiveError.self) { try ZipReader(data: bytes.prefix(bytes.count - 10)) }
        #expect(throws: ArchiveError.self) { try ZipReader(data: Data(repeating: 0x41, count: 500)) }
        #expect(throws: ArchiveError.self) { try ZipReader(data: Data()) }
        #expect(throws: ArchiveError.notAnArchive) { try ZipReader(data: Data("not a zip".utf8)) }
        #expect(throws: ArchiveError.truncated) { try ZipReader(data: Data([0x50, 0x4B, 0x03, 0x04])) }
    }

    @Test func rejectsEntriesPointingOutsideTheFile() throws {
        var bytes = try write([("a", Data(repeating: 1, count: 10))])
        // Local-header offset (bytes 42..45 of the central directory entry) set past the end of the file.
        let cd = bytes.count - 22 - (46 + 1)
        bytes.replaceSubrange((cd + 42)..<(cd + 46), with: [0xF0, 0xFF, 0xFF, 0x0F])
        let reader = try ZipReader(data: bytes)
        #expect(throws: ArchiveError.self) { try reader.read("a") }
    }

    @Test func rejectsCompressedEntries() throws {
        var bytes = try write([("a", Data(repeating: 1, count: 10))])
        let cd = bytes.count - 22 - (46 + 1)
        bytes[cd + 10] = 8   // method = deflate
        let reader = try ZipReader(data: bytes)
        #expect(throws: ArchiveError.self) { try reader.read("a") }
    }

    @Test func readsMissingEntryAsTypedError() throws {
        let reader = try ZipReader(data: try write([("a", Data())]))
        #expect(throws: ArchiveError.self) { try reader.read("b") }
    }

    @Test func writesToAFileAndReadsItBack() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "zip-\(UUID().uuidString).zip")
        defer { try? FileManager.default.removeItem(at: url) }
        let writer = try ZipWriter(url: url)
        try writer.add(name: "x/y.txt", data: Data("hi".utf8))
        try writer.finish()
        let reader = try ZipReader(url: url)
        #expect(try reader.read("x/y.txt") == Data("hi".utf8))
    }

    #if os(macOS)
    @Test func systemUnzipAcceptsOurArchives() throws {
        for zip64 in [false, true] {
            let url = FileManager.default.temporaryDirectory.appending(path: "zip-\(UUID().uuidString).zip")
            defer { try? FileManager.default.removeItem(at: url) }
            try write(sampleEntries(), zip64: zip64).write(to: url)
            let process = Process()
            process.executableURL = URL(filePath: "/usr/bin/unzip")
            process.arguments = ["-tq", url.path]
            process.standardOutput = Pipe()
            process.standardError = Pipe()
            try process.run()
            process.waitUntilExit()
            #expect(process.terminationStatus == 0, "unzip -t failed for zip64=\(zip64)")
        }
    }
    #endif
}
