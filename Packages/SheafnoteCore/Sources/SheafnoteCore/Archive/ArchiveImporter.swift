import Foundation
import SwiftData

public struct ArchiveImportSummary: Sendable, Equatable {
    public var manifest: ArchiveManifest
    /// New ids of the notebooks created, in archive order.
    public var notebookIDs: [UUID]
    /// New ids of the folders created (including the wrapper folder, if any).
    public var folderIDs: [UUID]
    public var pageCount: Int
}

/// Reads a `.sheafnote` archive and adds its contents as NEW copies: every record gets a fresh id and nothing already
/// in the library is touched, replaced or merged. The archive is validated completely before the first row is written,
/// and the rows are saved in a single transaction, so a bad file imports nothing.
@MainActor
public struct ArchiveImporter {
    let context: ModelContext
    let pages: PageStore

    public init(context: ModelContext, pages: PageStore) {
        self.context = context
        self.pages = pages
    }

    /// Reads and checks the manifest only (to show "12 notebooks, 340 pages" before importing).
    public func inspect(url: URL) throws -> ArchiveManifest {
        try Self.openManifest(ZipReader(url: url))
    }

    /// - Parameters:
    ///   - folderID: where the imported notebooks (and top-level folders) go; nil is the library root.
    ///   - wrapperFolderName: when set, everything is placed inside a new folder with this name.
    @discardableResult
    public func importArchive(from url: URL, into folderID: UUID? = nil, wrapperFolderName: String? = nil,
                              now: Date = .now,
                              progress: (@MainActor (Double) -> Void)? = nil) async throws -> ArchiveImportSummary {
        let reader = try ZipReader(url: url)
        let manifest = try Self.openManifest(reader)
        let library = try ArchiveJSON.decode(ArchiveLibrary.self, from: reader.read(ArchiveLayout.library), name: ArchiveLayout.library)
        try ArchiveValidator.validate(library, in: reader)
        progress?(0.05)

        let assetMap = try await importAssets(library.assets, from: reader, progress: progress)
        try Task.checkCancellation()
        var builder = RecordBuilder(context: context, reader: reader, library: library, assetMap: assetMap, now: now)
        do {
            let summary = try builder.insertAll(into: folderID, wrapperFolderName: wrapperFolderName, manifest: manifest)
            try Task.checkCancellation()
            try context.save()
            progress?(1)
            return summary
        } catch {
            context.rollback()
            throw error
        }
    }

    // MARK: Steps

    private static func openManifest(_ reader: ZipReader) throws -> ArchiveManifest {
        guard reader.contains(ArchiveLayout.manifest) else { throw ArchiveError.notAnArchive }
        let manifest = try ArchiveJSON.decode(ArchiveManifest.self, from: reader.read(ArchiveLayout.manifest), name: ArchiveLayout.manifest)
        guard manifest.format == ArchiveLayout.formatName else { throw ArchiveError.notAnArchive }
        guard manifest.formatVersion <= ArchiveLayout.currentFormatVersion else { throw ArchiveError.newerFormat(manifest.formatVersion) }
        return manifest
    }

    /// Stores the attached files (deduplicated by hash) and returns archive id -> local asset id.
    private func importAssets(_ assets: [ArchiveAsset], from reader: ZipReader,
                              progress: (@MainActor (Double) -> Void)?) async throws -> [UUID: UUID] {
        var map: [UUID: UUID] = [:]
        for (index, meta) in assets.enumerated() {
            try Task.checkCancellation()
            let data = try reader.read(ArchiveLayout.asset(meta.id))
            guard Hashing.sha256Hex(data) == meta.sha256 else { throw ArchiveError.corrupt("attached file \(meta.filename ?? meta.id.uuidString) doesn't match its checksum") }
            map[meta.id] = try pages.importAsset(data: data, kind: meta.kind, filename: meta.filename, uti: meta.uti).id
            progress?(0.05 + 0.6 * Double(index + 1) / Double(assets.count))
            if index % 4 == 3 { await Task.yield() }
        }
        return map
    }
}

/// Structural checks done before anything is written.
enum ArchiveValidator {
    static func validate(_ lib: ArchiveLibrary, in reader: ZipReader) throws {
        try requireUnique(lib.folders.map(\.id), "folders")
        try requireUnique(lib.notebooks.map(\.id), "notebooks")
        try requireUnique(lib.pages.map(\.id), "pages")
        try requireUnique(lib.elements.map(\.id), "elements")
        try requireUnique(lib.assets.map(\.id), "attached files")
        let notebooks = Set(lib.notebooks.map(\.id)), pageIDs = Set(lib.pages.map(\.id))
        let assets = Set(lib.assets.map(\.id)), cards = Set(lib.flashcards.map(\.id))
        for page in lib.pages {
            try require(notebooks.contains(page.notebookID), "a page without its notebook")
            try require(page.backgroundAssetID.map(assets.contains) ?? true, "a page background that isn't included")
            if page.hasInk { try need(ArchiveLayout.ink(page.id), reader) }
        }
        for e in lib.elements {
            try require(pageIDs.contains(e.pageID), "an element without its page")
            try require(e.assetID.map(assets.contains) ?? true, "an element file that isn't included")
        }
        for note in lib.outline { try require(notebooks.contains(note.notebookID), "an outline entry without its notebook") }
        for mark in lib.bookmarks { try require(pageIDs.contains(mark.pageID), "a bookmark without its page") }
        for rec in lib.audioRecordings {
            try require(notebooks.contains(rec.notebookID) && assets.contains(rec.assetID), "an audio recording without its parts")
        }
        for card in lib.flashcards {
            try require(notebooks.contains(card.notebookID), "a flashcard without its notebook")
            try need(ArchiveLayout.cardFront(card.id), reader)
            try need(ArchiveLayout.cardBack(card.id), reader)
        }
        for state in lib.studyStates { try require(cards.contains(state.flashcardID), "study progress without its flashcard") }
        for nb in lib.notebooks where nb.hasRichText { try need(ArchiveLayout.richText(nb.id), reader) }
        for saved in lib.savedElements {
            try need(ArchiveLayout.savedThumbnail(saved.id), reader)
            if saved.hasInk { try need(ArchiveLayout.savedInk(saved.id), reader) }
        }
        for asset in lib.assets { try need(ArchiveLayout.asset(asset.id), reader) }
    }

    private static func need(_ name: String, _ reader: ZipReader) throws {
        guard reader.contains(name) else { throw ArchiveError.missingEntry(name) }
    }

    private static func require(_ condition: Bool, _ what: String) throws {
        guard condition else { throw ArchiveError.corrupt(what) }
    }

    private static func requireUnique(_ ids: [UUID], _ what: String) throws {
        guard Set(ids).count == ids.count else { throw ArchiveError.corrupt("duplicate ids in \(what)") }
    }
}
