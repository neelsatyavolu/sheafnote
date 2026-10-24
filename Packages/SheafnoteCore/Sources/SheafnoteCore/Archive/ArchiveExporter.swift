import Foundation
import SwiftData

public enum ArchiveSelection: Sendable {
    case library
    case notebooks([UUID])
}

/// Collects the records in scope (alive items only; Recently Deleted is not backed up) into `ArchiveLibrary` plus the
/// blob files that go beside it.
@MainActor
struct ArchiveCollector {
    let context: ModelContext

    struct Blob {
        var name: String
        var data: @MainActor () throws -> Data
    }

    struct Collected {
        var library = ArchiveLibrary()
        var blobs: [Blob] = []
    }

    func collect(_ selection: ArchiveSelection) throws -> Collected {
        var out = Collected()
        let notebooks = try selectedNotebooks(selection)
        let notebookIDs = Set(notebooks.map(\.id))
        var folderIDs = Set<UUID>()
        if case .library = selection {
            let folders = try context.fetch(FetchDescriptor<Folder>(predicate: #Predicate { $0.deletedAt == nil }))
            folderIDs = Set(folders.map(\.id))
            out.library.folders = folders.map(Self.dto).sorted { $0.id.uuidString < $1.id.uuidString }
        }
        out.library.notebooks = notebooks.map { Self.dto($0, folderIDs: folderIDs) }
        for nb in notebooks where nb.richText?.isEmpty == false {
            let id = nb.id
            out.blobs.append(Blob(name: ArchiveLayout.richText(id)) { nb.richText ?? Data() })
        }
        let pages = try collectPages(notebookIDs, into: &out)
        let pageIDs = Set(pages.map(\.id))
        var assetIDs = Set(pages.compactMap(\.backgroundAssetID))
        try collectElements(pageIDs, assetIDs: &assetIDs, into: &out)
        try collectNotebookRecords(notebookIDs, pageIDs: pageIDs, assetIDs: &assetIDs, into: &out)
        if case .library = selection { try collectSavedElements(into: &out) }
        try collectAssets(assetIDs, into: &out)
        return out
    }

    // MARK: Pieces

    private func selectedNotebooks(_ selection: ArchiveSelection) throws -> [Notebook] {
        let all = try context.fetch(FetchDescriptor<Notebook>(predicate: #Predicate { $0.deletedAt == nil }))
        let chosen: [Notebook]
        switch selection {
        case .library: chosen = all
        case .notebooks(let ids): chosen = all.filter { ids.contains($0.id) }
        }
        return chosen.sorted { $0.id.uuidString < $1.id.uuidString }
    }

    private func collectPages(_ notebookIDs: Set<UUID>, into out: inout Collected) throws -> [Page] {
        let all = try context.fetch(FetchDescriptor<Page>(predicate: #Predicate { $0.deletedAt == nil }))
        let pages = all.filter { notebookIDs.contains($0.notebookID) }
            .sorted { ($0.notebookID.uuidString, $0.sortKey, $0.id.uuidString) < ($1.notebookID.uuidString, $1.sortKey, $1.id.uuidString) }
        for page in pages {
            let hasInk = page.inkData?.isEmpty == false
            out.library.pages.append(Self.dto(page, hasInk: hasInk))
            if hasInk { out.blobs.append(Blob(name: ArchiveLayout.ink(page.id)) { page.inkData ?? Data() }) }
        }
        return pages
    }

    private func collectElements(_ pageIDs: Set<UUID>, assetIDs: inout Set<UUID>, into out: inout Collected) throws {
        let all = try context.fetch(FetchDescriptor<PageElement>(predicate: #Predicate { $0.deletedAt == nil }))
        for e in all.filter({ pageIDs.contains($0.pageID) }).sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            if let asset = e.assetID { assetIDs.insert(asset) }
            out.library.elements.append(ArchiveElement(
                id: e.id, pageID: e.pageID, kind: e.kind, x: e.x, y: e.y, width: e.width, height: e.height,
                rotation: e.rotation, zIndex: e.zIndex, payload: e.payload, assetID: e.assetID,
                createdAt: e.createdAt, modifiedAt: e.modifiedAt))
        }
    }

    private func collectNotebookRecords(_ ids: Set<UUID>, pageIDs: Set<UUID>, assetIDs: inout Set<UUID>,
                                        into out: inout Collected) throws {
        let outline = try context.fetch(FetchDescriptor<OutlineEntry>(predicate: #Predicate { $0.deletedAt == nil }))
        out.library.outline = outline.filter { ids.contains($0.notebookID) }.sorted { $0.id.uuidString < $1.id.uuidString }.map {
            ArchiveOutlineEntry(id: $0.id, notebookID: $0.notebookID, title: $0.title, pageID: $0.pageID,
                                pdfPageIndex: $0.pdfPageIndex, parentID: $0.parentID, sortKey: $0.sortKey, source: $0.source)
        }
        let bookmarks = try context.fetch(FetchDescriptor<Bookmark>(predicate: #Predicate { $0.deletedAt == nil }))
        out.library.bookmarks = bookmarks.filter { ids.contains($0.notebookID) && pageIDs.contains($0.pageID) }
            .sorted { $0.id.uuidString < $1.id.uuidString }
            .map { ArchiveBookmark(id: $0.id, notebookID: $0.notebookID, pageID: $0.pageID, title: $0.title) }
        let audio = try context.fetch(FetchDescriptor<AudioRecording>(predicate: #Predicate { $0.deletedAt == nil }))
        for a in audio.filter({ ids.contains($0.notebookID) }).sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            assetIDs.insert(a.assetID)
            out.library.audioRecordings.append(ArchiveAudioRecording(
                id: a.id, notebookID: a.notebookID, assetID: a.assetID, title: a.title, startedAt: a.startedAt,
                duration: a.duration, timeline: a.timeline))
        }
        try collectFlashcards(ids, into: &out)
    }

    private func collectFlashcards(_ ids: Set<UUID>, into out: inout Collected) throws {
        let cards = try context.fetch(FetchDescriptor<Flashcard>(predicate: #Predicate { $0.deletedAt == nil }))
        let chosen = cards.filter { ids.contains($0.notebookID) }.sorted { $0.id.uuidString < $1.id.uuidString }
        for card in chosen {
            out.library.flashcards.append(ArchiveFlashcard(id: card.id, notebookID: card.notebookID, deck: card.deck,
                                                           sourcePageID: card.sourcePageID, frontText: card.frontText,
                                                           backText: card.backText))
            out.blobs.append(Blob(name: ArchiveLayout.cardFront(card.id)) { card.frontImage })
            out.blobs.append(Blob(name: ArchiveLayout.cardBack(card.id)) { card.backImage })
        }
        let cardIDs = Set(chosen.map(\.id))
        let states = try context.fetch(FetchDescriptor<StudyState>(predicate: #Predicate { $0.deletedAt == nil }))
        out.library.studyStates = states.filter { cardIDs.contains($0.flashcardID) }.sorted { $0.id.uuidString < $1.id.uuidString }.map {
            ArchiveStudyState(id: $0.id, flashcardID: $0.flashcardID, ease: $0.ease, intervalDays: $0.intervalDays,
                              repetitions: $0.repetitions, lapses: $0.lapses, dueAt: $0.dueAt, lastReviewedAt: $0.lastReviewedAt)
        }
    }

    private func collectSavedElements(into out: inout Collected) throws {
        let rows = try context.fetch(FetchDescriptor<SavedElement>(predicate: #Predicate { $0.deletedAt == nil }))
        for s in rows.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            let hasInk = s.inkData?.isEmpty == false
            out.library.savedElements.append(ArchiveSavedElement(id: s.id, name: s.name, category: s.category, width: s.width,
                                                                 height: s.height, hasInk: hasInk, elements: s.elements))
            if hasInk { out.blobs.append(Blob(name: ArchiveLayout.savedInk(s.id)) { s.inkData ?? Data() }) }
            out.blobs.append(Blob(name: ArchiveLayout.savedThumbnail(s.id)) { s.thumbnail })
        }
    }

    private func collectAssets(_ ids: Set<UUID>, into out: inout Collected) throws {
        for id in ids.sorted(by: { $0.uuidString < $1.uuidString }) {
            guard let asset = try context.fetch(FetchDescriptor<Asset>(predicate: #Predicate { $0.id == id })).first else {
                throw StoreError.invalid("A page refers to an attached file that is missing from this device, so the backup can't be completed.")
            }
            out.library.assets.append(ArchiveAsset(id: id, kind: asset.kind, sha256: asset.sha256,
                                                   byteCount: asset.byteCount, filename: asset.filename, uti: asset.uti))
            let expected = asset.sha256
            out.blobs.append(Blob(name: ArchiveLayout.asset(id)) {
                let data = asset.data
                guard Hashing.sha256Hex(data) == expected else {
                    throw StoreError.invalid("An attached file on this device is damaged, so the backup was stopped instead of saving a bad copy.")
                }
                return data
            })
        }
    }

    // MARK: DTOs

    private static func dto(_ f: Folder) -> ArchiveFolder {
        ArchiveFolder(id: f.id, name: f.name, parentID: f.parentID, sortKey: f.sortKey, isFavorite: f.isFavorite,
                      colorName: f.colorName, createdAt: f.createdAt, modifiedAt: f.modifiedAt)
    }

    private static func dto(_ n: Notebook, folderIDs: Set<UUID>) -> ArchiveNotebook {
        let parent = n.folderID.flatMap { folderIDs.contains($0) ? $0 : nil }
        return ArchiveNotebook(
            id: n.id, title: n.title, kind: n.kind, folderID: parent, cover: n.cover, template: n.template,
            paperSize: n.paperSize, orientation: n.orientation, paperColor: n.paperColor, scrollDirection: n.scrollDirection,
            isFavorite: n.isFavorite, isLocked: n.isLocked, sortKey: n.sortKey, pdfOutlineImported: n.pdfOutlineImported,
            hasRichText: n.richText?.isEmpty == false, createdAt: n.createdAt, modifiedAt: n.modifiedAt)
    }

    private static func dto(_ p: Page, hasInk: Bool) -> ArchivePage {
        ArchivePage(id: p.id, notebookID: p.notebookID, sortKey: p.sortKey, width: p.widthPts, height: p.heightPts,
                    templateOverride: p.template, paperColorOverride: p.paperColorOverride,
                    backgroundAssetID: p.backgroundAssetID, backgroundPageIndex: p.backgroundPageIndex,
                    strokeIDs: p.strokeIDs, inkHash: p.inkHash, recognizedText: p.recognizedText, ocrInkHash: p.ocrInkHash,
                    isInfinite: p.isInfinite, hasInk: hasInk, createdAt: p.createdAt, modifiedAt: p.modifiedAt)
    }
}

/// Writes a `.sheafnote` archive of the whole library or of chosen notebooks.
@MainActor
public struct ArchiveExporter {
    private let context: ModelContext
    private let appVersion: String

    public init(context: ModelContext, appVersion: String = "1") {
        self.context = context
        self.appVersion = appVersion
    }

    /// Writes to `url` (replacing nothing: the file must not exist yet). A partly written file is removed on failure.
    /// `progress` receives 0...1.
    @discardableResult
    public func export(_ selection: ArchiveSelection, to url: URL, now: Date = .now,
                       progress: (@MainActor (Double) -> Void)? = nil) async throws -> ArchiveManifest {
        let collected = try ArchiveCollector(context: context).collect(selection)
        let manifest = ArchiveManifest(format: ArchiveLayout.formatName, formatVersion: ArchiveLayout.currentFormatVersion,
                                       createdAt: now, appVersion: appVersion,
                                       scope: { if case .library = selection { .library } else { .notebooks } }(),
                                       counts: collected.library.counts)
        do {
            let writer = try ZipWriter(url: url)
            try writer.add(name: ArchiveLayout.manifest, data: try ArchiveJSON.encode(manifest))
            try writer.add(name: ArchiveLayout.library, data: try ArchiveJSON.encode(collected.library))
            for (index, blob) in collected.blobs.enumerated() {
                try Task.checkCancellation()
                try writer.add(name: blob.name, data: try blob.data())
                progress?(Double(index + 1) / Double(collected.blobs.count))
                if index % 8 == 7 { await Task.yield() }
            }
            try writer.finish()
        } catch {
            try? FileManager.default.removeItem(at: url)
            throw error
        }
        progress?(1)
        return manifest
    }
}
