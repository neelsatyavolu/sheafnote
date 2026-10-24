import Foundation
import SwiftData
import Testing
@testable import SheafnoteCore

/// Corrupt, hostile and too-new archives are rejected with a typed error and import nothing.
@MainActor
@Suite("Archive rejection")
struct ArchiveRejectTests {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    private func notebook(id: UUID = UUID()) -> ArchiveNotebook {
        ArchiveNotebook(id: id, title: "N", kind: .paged, folderID: nil, cover: .default, template: .blank, paperSize: "a4",
                        orientation: "portrait", paperColor: "white", scrollDirection: "vertical", isFavorite: false,
                        isLocked: false, sortKey: "V", pdfOutlineImported: false, hasRichText: false, createdAt: t0, modifiedAt: t0)
    }

    private func page(_ id: UUID, in nb: UUID, hasInk: Bool = false, asset: UUID? = nil) -> ArchivePage {
        ArchivePage(id: id, notebookID: nb, sortKey: "V", width: 595, height: 842, templateOverride: nil, paperColorOverride: nil,
                    backgroundAssetID: asset, backgroundPageIndex: nil, strokeIDs: [], inkHash: "", recognizedText: "",
                    ocrInkHash: "", isInfinite: false, hasInk: hasInk, createdAt: t0, modifiedAt: t0)
    }

    private func manifest(version: Int = 1, format: String = ArchiveLayout.formatName) -> ArchiveManifest {
        ArchiveManifest(format: format, formatVersion: version, createdAt: t0, appVersion: "1", scope: .library, counts: ArchiveCounts())
    }

    private func build(manifest: ArchiveManifest?, library: ArchiveLibrary?, extra: [(String, Data)] = []) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "reject-\(UUID().uuidString).sheafnote")
        let writer = try ZipWriter(url: url)
        if let manifest { try writer.add(name: ArchiveLayout.manifest, data: ArchiveJSON.encode(manifest)) }
        if let library { try writer.add(name: ArchiveLayout.library, data: ArchiveJSON.encode(library)) }
        for (name, data) in extra { try writer.add(name: name, data: data) }
        try writer.finish()
        return url
    }

    private func attempt(_ url: URL, fixture: StoreFixture) async -> Error? {
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            _ = try await ArchiveImporter(context: fixture.context, pages: fixture.pages).importArchive(from: url)
            return nil
        } catch { return error }
    }

    private func notebooksInStore(_ fx: StoreFixture) throws -> Int { try fx.library.allNotebooks().count }

    @Test func notAZipIsNotAnArchive() async throws {
        let fx = try StoreFixture()
        let url = FileManager.default.temporaryDirectory.appending(path: "x-\(UUID().uuidString).sheafnote")
        try Data("hello world, definitely not a zip file".utf8).write(to: url)
        #expect(await attempt(url, fixture: fx) as? ArchiveError == .notAnArchive)
    }

    @Test func zipWithoutManifestIsNotAnArchive() async throws {
        let fx = try StoreFixture()
        let url = try build(manifest: nil, library: ArchiveLibrary())
        #expect(await attempt(url, fixture: fx) as? ArchiveError == .notAnArchive)
    }

    @Test func wrongFormatNameIsNotAnArchive() async throws {
        let fx = try StoreFixture()
        let url = try build(manifest: manifest(format: "something-else"), library: ArchiveLibrary())
        #expect(await attempt(url, fixture: fx) as? ArchiveError == .notAnArchive)
    }

    @Test func newerFormatVersionIsRefusedWithTheVersion() async throws {
        let fx = try StoreFixture()
        let url = try build(manifest: manifest(version: 99), library: ArchiveLibrary())
        #expect(await attempt(url, fixture: fx) as? ArchiveError == .newerFormat(99))
    }

    @Test func unknownKeysFromANewerWriterAreIgnored() async throws {
        let fx = try StoreFixture()
        let json = #"{"format":"sheafnote-archive","formatVersion":1,"createdAt":"2026-01-01T00:00:00Z","appVersion":"9","scope":"library","counts":{"folders":0,"notebooks":0,"pages":0,"elements":0,"assets":0,"future":5},"extra":true}"#
        let url = FileManager.default.temporaryDirectory.appending(path: "future-\(UUID().uuidString).sheafnote")
        let writer = try ZipWriter(url: url)
        try writer.add(name: ArchiveLayout.manifest, data: Data(json.utf8))
        try writer.add(name: ArchiveLayout.library, data: Data(#"{"notebooks":[],"somethingNew":[1,2]}"#.utf8))
        try writer.finish()
        #expect(await attempt(url, fixture: fx) == nil)
    }

    @Test func missingInkFileRejectsTheWholeImport() async throws {
        let fx = try StoreFixture()
        var lib = ArchiveLibrary()
        let nb = notebook()
        lib.notebooks = [nb]
        lib.pages = [page(UUID(), in: nb.id, hasInk: true)]
        let url = try build(manifest: manifest(), library: lib)
        let error = await attempt(url, fixture: fx)
        guard case .missingEntry? = error as? ArchiveError else { Issue.record("expected missingEntry, got \(String(describing: error))"); return }
        #expect(try notebooksInStore(fx) == 0)
    }

    @Test func pageWithoutItsNotebookIsCorrupt() async throws {
        let fx = try StoreFixture()
        var lib = ArchiveLibrary()
        lib.pages = [page(UUID(), in: UUID())]
        let url = try build(manifest: manifest(), library: lib)
        guard case .corrupt? = await attempt(url, fixture: fx) as? ArchiveError else { Issue.record("expected corrupt"); return }
    }

    @Test func duplicateIdsAreCorrupt() async throws {
        let fx = try StoreFixture()
        var lib = ArchiveLibrary()
        let nb = notebook()
        lib.notebooks = [nb, nb]
        let url = try build(manifest: manifest(), library: lib)
        guard case .corrupt? = await attempt(url, fixture: fx) as? ArchiveError else { Issue.record("expected corrupt"); return }
    }

    @Test func tamperedAssetFailsItsChecksumAndLeavesNoNotebook() async throws {
        let fx = try StoreFixture()
        var lib = ArchiveLibrary()
        let nb = notebook(), assetID = UUID()
        lib.notebooks = [nb]
        lib.pages = [page(UUID(), in: nb.id, asset: assetID)]
        lib.assets = [ArchiveAsset(id: assetID, kind: .pdf, sha256: String(repeating: "0", count: 64), byteCount: 3, filename: nil, uti: nil)]
        let url = try build(manifest: manifest(), library: lib, extra: [(ArchiveLayout.asset(assetID), Data([1, 2, 3]))])
        guard case .corrupt? = await attempt(url, fixture: fx) as? ArchiveError else { Issue.record("expected corrupt"); return }
        #expect(try notebooksInStore(fx) == 0)
    }

    @Test func cyclicFoldersAreFlattenedToTheTopInsteadOfHidden() async throws {
        let fx = try StoreFixture()
        var lib = ArchiveLibrary()
        let a = UUID(), b = UUID()
        func folder(_ id: UUID, parent: UUID) -> ArchiveFolder {
            ArchiveFolder(id: id, name: "F", parentID: parent, sortKey: "V", isFavorite: false, colorName: nil, createdAt: t0, modifiedAt: t0)
        }
        lib.folders = [folder(a, parent: b), folder(b, parent: a)]
        let url = try build(manifest: manifest(), library: lib)
        #expect(await attempt(url, fixture: fx) == nil)
        let folders = try fx.library.allFolders()
        #expect(folders.count == 2 && folders.allSatisfy { $0.parentID == nil })
    }

    @Test func remapperOnlyTouchesKnownIds() {
        let old = UUID(), new = UUID(), stranger = UUID()
        let json = Data(#"{"a":["\#(old.uuidString)","\#(stranger.uuidString)"],"n":1.5}"#.utf8)
        let out = String(decoding: UUIDRemapper.remap(json, using: [old: new]), as: UTF8.self)
        #expect(out.contains(new.uuidString) && out.contains(stranger.uuidString) && !out.contains(old.uuidString))
        let untouched = Data("not json".utf8)
        #expect(UUIDRemapper.remap(untouched, using: [old: new]) == untouched)
        #expect(UUIDRemapper.remap(json, using: [:]) == json)
    }
}
