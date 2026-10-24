import Foundation
import SwiftData

/// Turns a validated `ArchiveLibrary` into new SwiftData rows with fresh ids. Nothing is saved here; the importer
/// saves once at the end (and rolls back on any error).
@MainActor
struct RecordBuilder {
    let context: ModelContext
    let reader: ZipReader
    let library: ArchiveLibrary
    let assetMap: [UUID: UUID]
    let now: Date
    private var ids: [UUID: UUID] = [:]

    init(context: ModelContext, reader: ZipReader, library: ArchiveLibrary, assetMap: [UUID: UUID], now: Date) {
        self.context = context
        self.reader = reader
        self.library = library
        self.assetMap = assetMap
        self.now = now
    }

    mutating func insertAll(into folderID: UUID?, wrapperFolderName: String?, manifest: ArchiveManifest) throws -> ArchiveImportSummary {
        allocateIDs()
        var summary = ArchiveImportSummary(manifest: manifest, notebookIDs: [], folderIDs: [], pageCount: 0)
        var root = folderID
        if let name = wrapperFolderName {
            let wrapper = Folder(name: name, parentID: folderID, sortKey: SortKey.between(nil, nil), now: now)
            context.insert(wrapper)
            markDirty(wrapper, fields: ["name", "parentID", "sortKey", "isFavorite"], now: now)
            summary.folderIDs.append(wrapper.id)
            root = wrapper.id
        }
        summary.folderIDs += insertFolders(root: root)
        for nb in library.notebooks {
            summary.notebookIDs.append(try insertNotebook(nb, root: root).id)
        }
        summary.pageCount = try insertPages()
        insertElements()
        insertOutlineAndBookmarks()
        try insertStudyMaterial()
        try insertSavedElements()
        return summary
    }

    // MARK: Ids

    private mutating func allocateIDs() {
        let old: [UUID] = library.folders.map(\.id) + library.notebooks.map(\.id) + library.pages.map(\.id)
            + library.elements.map(\.id) + library.outline.map(\.id) + library.bookmarks.map(\.id)
            + library.audioRecordings.map(\.id) + library.flashcards.map(\.id) + library.studyStates.map(\.id)
            + library.savedElements.map(\.id)
        for id in old { ids[id] = UUID() }
    }

    private func new(_ id: UUID) -> UUID { ids[id] ?? id }
    private func new(_ id: UUID?) -> UUID? { id.flatMap { ids[$0] } }

    /// Map used inside payload JSON: record ids to new ids (asset ids are never referenced from payloads).
    private var jsonMap: [UUID: UUID] { ids }

    /// Flags the new row for sync but keeps the archive's modification date, so "last edited" survives a restore.
    private func stamp<T: SyncableRecord>(_ row: T, fields: [String], modified: Date) {
        markDirty(row, fields: fields, now: now)
        row.modifiedAt = modified
    }

    // MARK: Library

    private func insertFolders(root: UUID?) -> [UUID] {
        let known = Set(library.folders.map(\.id))
        let parents = Dictionary(uniqueKeysWithValues: library.folders.map { ($0.id, $0.parentID) })
        var created: [UUID] = []
        for f in library.folders {
            // A missing parent or a loop in the file would hide the folder, so it goes to the top instead.
            let parent = Self.hasCycle(from: f.id, parents: parents) ? nil : f.parentID.flatMap { known.contains($0) ? $0 : nil }
            let row = Folder(id: new(f.id), name: f.name, parentID: parent.map(new) ?? root, sortKey: f.sortKey,
                             isFavorite: f.isFavorite, colorName: f.colorName, now: now)
            context.insert(row)
            row.createdAt = f.createdAt
            stamp(row, fields: ["name", "parentID", "sortKey", "isFavorite"], modified: f.modifiedAt)
            created.append(row.id)
        }
        return created
    }

    private static func hasCycle(from start: UUID, parents: [UUID: UUID?]) -> Bool {
        var current: UUID? = start
        for _ in 0...parents.count {
            guard let id = current, let next = parents[id] else { return false }
            current = next
            if current == start { return true }
        }
        return true
    }

    private func insertNotebook(_ n: ArchiveNotebook, root: UUID?) throws -> Notebook {
        let parent = n.folderID.flatMap { ids[$0] } ?? root
        let row = Notebook(id: new(n.id), title: n.title, kind: n.kind, folderID: parent, cover: n.cover, template: n.template,
                           paperSize: PaperSize(rawValue: n.paperSize) ?? .a4,
                           orientation: PageOrientation(rawValue: n.orientation) ?? .portrait,
                           paperColor: PaperColor(rawValue: n.paperColor) ?? .white, sortKey: n.sortKey, now: now)
        row.scrollDirection = ScrollDirection(rawValue: n.scrollDirection)?.rawValue ?? ScrollDirection.vertical.rawValue
        row.isFavorite = n.isFavorite
        row.isLocked = n.isLocked
        row.pdfOutlineImported = n.pdfOutlineImported
        if n.hasRichText { row.richText = try reader.read(ArchiveLayout.richText(n.id)) }
        context.insert(row)
        row.createdAt = n.createdAt
        stamp(row, fields: LibraryStore.notebookFields, modified: n.modifiedAt)
        return row
    }

    // MARK: Pages and elements

    private func insertPages() throws -> Int {
        for p in library.pages {
            let row = Page(id: new(p.id), notebookID: new(p.notebookID), sortKey: p.sortKey,
                           size: CGSize(width: p.width, height: p.height), isInfinite: p.isInfinite, now: now)
            row.templateOverride = p.templateOverride.map { JSONCoding.encode($0) }
            row.paperColorOverride = p.paperColorOverride
            row.backgroundAssetID = p.backgroundAssetID.flatMap { assetMap[$0] }
            row.backgroundPageIndex = p.backgroundPageIndex
            row.strokeIDs = p.strokeIDs
            row.inkHash = p.inkHash
            row.recognizedText = p.recognizedText
            row.ocrInkHash = p.ocrInkHash
            if p.hasInk { row.inkData = try reader.read(ArchiveLayout.ink(p.id)) }
            context.insert(row)
            row.createdAt = p.createdAt
            stamp(row, fields: LibraryStore.pageFields, modified: p.modifiedAt)
        }
        return library.pages.count
    }

    private func insertElements() {
        for e in library.elements {
            let value = ElementValue(id: new(e.id), pageID: new(e.pageID), kind: e.kind,
                                     frame: CGRect(x: e.x, y: e.y, width: e.width, height: e.height), rotation: e.rotation,
                                     zIndex: e.zIndex, payload: UUIDRemapper.remap(e.payload, using: jsonMap),
                                     assetID: e.assetID.flatMap { assetMap[$0] })
            let row = PageElement(value: value, now: now)
            context.insert(row)
            markDirty(row, fields: ["kind", "x", "y", "width", "height", "rotation", "zIndex", "payload", "assetID"], now: now)
            row.modifiedAt = e.modifiedAt
        }
    }

    private func insertOutlineAndBookmarks() {
        for o in library.outline {
            let row = OutlineEntry(id: new(o.id), notebookID: new(o.notebookID), title: o.title, pageID: new(o.pageID),
                                   pdfPageIndex: o.pdfPageIndex, parentID: new(o.parentID), sortKey: o.sortKey,
                                   source: OutlineSource(rawValue: o.source) ?? .user, now: now)
            context.insert(row)
            markDirty(row, fields: ["notebookID", "title", "pageID", "pdfPageIndex", "parentID", "sortKey", "source"], now: now)
        }
        for b in library.bookmarks {
            let row = Bookmark(id: new(b.id), notebookID: new(b.notebookID), pageID: new(b.pageID), title: b.title, now: now)
            context.insert(row)
            markDirty(row, fields: ["notebookID", "pageID", "title"], now: now)
        }
    }

    // MARK: Study, audio, saved elements

    private func insertStudyMaterial() throws {
        for a in library.audioRecordings {
            let row = AudioRecording(id: new(a.id), notebookID: new(a.notebookID), assetID: assetMap[a.assetID] ?? a.assetID,
                                     title: a.title, startedAt: a.startedAt, duration: a.duration,
                                     timeline: UUIDRemapper.remap(a.timeline, using: jsonMap), now: now)
            context.insert(row)
            markDirty(row, fields: ["notebookID", "assetID", "title", "startedAt", "duration", "timeline"], now: now)
        }
        for c in library.flashcards {
            let row = Flashcard(id: new(c.id), notebookID: new(c.notebookID), deck: c.deck, sourcePageID: new(c.sourcePageID),
                                frontImage: try reader.read(ArchiveLayout.cardFront(c.id)),
                                backImage: try reader.read(ArchiveLayout.cardBack(c.id)),
                                frontText: c.frontText, backText: c.backText, now: now)
            context.insert(row)
            markDirty(row, fields: ["notebookID", "deck", "sourcePageID", "frontImage", "backImage", "frontText", "backText"], now: now)
        }
        for s in library.studyStates {
            let row = StudyState(id: new(s.id), flashcardID: new(s.flashcardID), dueAt: s.dueAt, now: now)
            row.ease = s.ease
            row.intervalDays = s.intervalDays
            row.repetitions = s.repetitions
            row.lapses = s.lapses
            row.lastReviewedAt = s.lastReviewedAt
            context.insert(row)
            markDirty(row, fields: ["flashcardID", "ease", "intervalDays", "repetitions", "lapses", "dueAt", "lastReviewedAt"], now: now)
        }
    }

    private func insertSavedElements() throws {
        for s in library.savedElements {
            let row = SavedElement(id: new(s.id), name: s.name, category: s.category, width: s.width, height: s.height,
                                   inkData: s.hasInk ? try reader.read(ArchiveLayout.savedInk(s.id)) : nil,
                                   elements: s.elements, thumbnail: try reader.read(ArchiveLayout.savedThumbnail(s.id)), now: now)
            context.insert(row)
            markDirty(row, fields: ["name", "category", "width", "height", "inkData", "elements", "thumbnail"], now: now)
        }
    }
}
