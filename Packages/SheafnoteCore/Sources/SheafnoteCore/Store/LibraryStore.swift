import Foundation
import SwiftData

/// Folders and notebooks. Every mutation calls `markDirty`. Nothing here removes data except
/// `purgeExpired` (items deleted more than 30 days ago) and `deletePermanently` (items already in Recently Deleted).
@MainActor
public final class LibraryStore {
    let context: ModelContext
    /// Called with the rows removed for good, so sync can delete their CloudKit records.
    public var onPurge: (@MainActor ([PurgedRecord]) -> Void)?

    public init(context: ModelContext) { self.context = context }

    // MARK: Fetching

    public func allFolders() throws -> [Folder] { try context.fetch(FetchDescriptor<Folder>()) }
    public func allNotebooks() throws -> [Notebook] { try context.fetch(FetchDescriptor<Notebook>()) }

    public func notebook(id: UUID) -> Notebook? {
        try? context.fetch(FetchDescriptor<Notebook>(predicate: #Predicate { $0.id == id })).first
    }

    public func folder(id: UUID) -> Folder? {
        try? context.fetch(FetchDescriptor<Folder>(predicate: #Predicate { $0.id == id })).first
    }

    // MARK: Creating

    @discardableResult
    public func createNotebook(title: String, kind: NotebookKind, cover: CoverSpec, template: TemplateSpec,
                               paperSize: PaperSize, orientation: PageOrientation, paperColor: PaperColor,
                               in folder: UUID?, now: Date = .now) throws -> Notebook {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = SortKey.between(try lastNotebookKey(in: folder), nil)
        let notebook = Notebook(title: trimmed, kind: kind, folderID: folder, cover: cover, template: template,
                                paperSize: paperSize, orientation: orientation, paperColor: paperColor, sortKey: key, now: now)
        context.insert(notebook)
        if kind != .text {
            let page = Page(notebookID: notebook.id, sortKey: SortKey.between(nil, nil), size: notebook.pageSize,
                            isInfinite: kind == .whiteboard, now: now)
            context.insert(page)
            markDirty(page, fields: ["sortKey", "widthPts", "heightPts"], now: now)
        }
        markDirty(notebook, fields: Self.notebookFields, now: now)
        try context.save()
        return notebook
    }

    @discardableResult
    public func createFolder(name: String, in parent: UUID?, now: Date = .now) throws -> Folder {
        let key = SortKey.between(try lastFolderKey(in: parent), nil)
        let folder = Folder(name: name.trimmingCharacters(in: .whitespacesAndNewlines), parentID: parent, sortKey: key, now: now)
        context.insert(folder)
        markDirty(folder, fields: ["name", "parentID", "sortKey", "isFavorite"], now: now)
        try context.save()
        return folder
    }

    // MARK: Editing

    public func rename(_ item: LibraryItemRef, to name: String, now: Date = .now) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw StoreError.invalid("A name can't be empty.") }
        switch item {
        case .folder(let id):
            let f = try requireFolder(id)
            f.name = trimmed
            markDirty(f, fields: ["name"], now: now)
        case .notebook(let id):
            let n = try requireNotebook(id)
            n.title = trimmed
            markDirty(n, fields: ["title"], now: now)
        }
        try context.save()
    }

    public func setFavorite(_ items: [LibraryItemRef], _ value: Bool, now: Date = .now) throws {
        for item in items {
            switch item {
            case .folder(let id):
                let f = try requireFolder(id)
                f.isFavorite = value
                markDirty(f, fields: ["isFavorite"], now: now)
            case .notebook(let id):
                let n = try requireNotebook(id)
                n.isFavorite = value
                markDirty(n, fields: ["isFavorite"], now: now)
            }
        }
        try context.save()
    }

    public func setCover(_ notebookID: UUID, to cover: CoverSpec, now: Date = .now) throws {
        let n = try requireNotebook(notebookID)
        n.cover = cover
        markDirty(n, fields: ["coverSpec"], now: now)
        try context.save()
    }

    /// Local-only bookkeeping (not synced); does not touch `modifiedAt`.
    public func recordOpened(_ notebookID: UUID, now: Date = .now) throws {
        let n = try requireNotebook(notebookID)
        n.lastOpenedAt = now
        try context.save()
    }

    public func move(_ items: [LibraryItemRef], to folder: UUID?, now: Date = .now) throws {
        if let folder {
            let target = try requireFolder(folder)
            guard target.deletedAt == nil else { throw StoreError.invalid("That folder is in Recently Deleted.") }
        }
        let folders = try allFolders()
        for item in items {
            switch item {
            case .folder(let id):
                if let folder, Self.isFolder(folder, insideOrEqualTo: id, in: folders) {
                    throw StoreError.invalid("A folder can't be moved into itself.")
                }
                let f = try requireFolder(id)
                f.parentID = folder
                f.sortKey = SortKey.between(try lastFolderKey(in: folder), nil)
                markDirty(f, fields: ["parentID", "sortKey"], now: now)
            case .notebook(let id):
                let n = try requireNotebook(id)
                n.folderID = folder
                n.sortKey = SortKey.between(try lastNotebookKey(in: folder), nil)
                markDirty(n, fields: ["folderID", "sortKey"], now: now)
            }
        }
        try context.save()
    }

    // MARK: Soft delete and restore

    /// Sets `deletedAt`; nothing is removed. Deleting a folder also marks its contents with the same timestamp.
    public func softDelete(_ items: [LibraryItemRef], now: Date = .now) throws {
        let folders = try allFolders()
        let notebooks = try allNotebooks()
        for item in items {
            switch item {
            case .folder(let id):
                for f in Self.subtreeFolders(of: id, in: folders) where f.deletedAt == nil {
                    f.deletedAt = now
                    markDirty(f, fields: ["deletedAt"], now: now)
                }
                let ids = Set(Self.subtreeFolders(of: id, in: folders).map(\.id))
                for n in notebooks where n.deletedAt == nil && n.folderID.map(ids.contains) == true {
                    n.deletedAt = now
                    markDirty(n, fields: ["deletedAt"], now: now)
                }
            case .notebook(let id):
                let n = try requireNotebook(id)
                if n.deletedAt == nil {
                    n.deletedAt = now
                    markDirty(n, fields: ["deletedAt"], now: now)
                }
            }
        }
        try context.save()
    }

    /// Restores items; a folder brings back what was deleted along with it. Items whose parent folder
    /// is still deleted (or gone) return to the top level.
    public func restore(_ items: [LibraryItemRef], now: Date = .now) throws {
        let folders = try allFolders()
        let notebooks = try allNotebooks()
        for item in items {
            switch item {
            case .folder(let id):
                let f = try requireFolder(id)
                guard let stamp = f.deletedAt else { continue }
                let subtree = Self.subtreeFolders(of: id, in: folders)
                let ids = Set(subtree.map(\.id))
                for sub in subtree where sub.deletedAt == stamp { sub.deletedAt = nil; markDirty(sub, fields: ["deletedAt"], now: now) }
                for n in notebooks where n.deletedAt == stamp && n.folderID.map(ids.contains) == true {
                    n.deletedAt = nil
                    markDirty(n, fields: ["deletedAt"], now: now)
                }
                if let parent = f.parentID, !Self.isLive(folderID: parent, in: folders) {
                    f.parentID = nil
                    markDirty(f, fields: ["parentID"], now: now)
                }
            case .notebook(let id):
                let n = try requireNotebook(id)
                guard n.deletedAt != nil else { continue }
                n.deletedAt = nil
                markDirty(n, fields: ["deletedAt"], now: now)
                if let parent = n.folderID, !Self.isLive(folderID: parent, in: folders) {
                    n.folderID = nil
                    markDirty(n, fields: ["folderID"], now: now)
                }
            }
        }
        try context.save()
    }

    /// Live notebooks and folders inside a folder that sits in Recently Deleted would show up nowhere: not at the top
    /// level, not in the deleted folder's listing, not in Recently Deleted. A sync merge can produce that (one device
    /// deleted the folder while another added to it), so such items move to the top level. A parent that is merely
    /// missing is left alone: it may still be on its way from iCloud.
    @discardableResult
    public func reparentOrphans(now: Date = .now) throws -> Int {
        let folders = try allFolders()
        let deleted = Set(folders.filter { $0.deletedAt != nil }.map(\.id))
        guard !deleted.isEmpty else { return 0 }
        var moved = 0
        for f in folders where f.deletedAt == nil && f.parentID.map(deleted.contains) == true {
            f.parentID = nil
            markDirty(f, fields: ["parentID"], now: now)
            moved += 1
        }
        for n in try allNotebooks() where n.deletedAt == nil && n.folderID.map(deleted.contains) == true {
            n.folderID = nil
            markDirty(n, fields: ["folderID"], now: now)
            moved += 1
        }
        if moved > 0 { try context.save() }
        return moved
    }

    // MARK: Permanent removal

    /// Removes rows deleted more than 30 days before `now`. Returns the number of folders and notebooks removed.
    @discardableResult
    public func purgeExpired(now: Date = .now) throws -> Int {
        let cutoff = now.addingTimeInterval(-Retention.seconds)
        try reparentOrphans(now: now)   // never purge a folder out from under live items
        let purger = LibraryPurger(context: context)
        let result = try purger.purge(olderThan: cutoff)
        if !result.records.isEmpty { onPurge?(result.records) }
        return result.libraryItems
    }

    /// "Delete Permanently" / "Empty": only items already in Recently Deleted can be removed this way.
    @discardableResult
    public func deletePermanently(_ items: [LibraryItemRef]) throws -> Int {
        let purger = LibraryPurger(context: context)
        let result = try purger.erase(items)
        if !result.records.isEmpty { onPurge?(result.records) }
        return result.libraryItems
    }

    // MARK: Duplicate

    @discardableResult
    public func duplicate(_ notebook: Notebook, copySuffix: String = " copy", now: Date = .now) throws -> Notebook {
        let key = SortKey.between(try lastNotebookKey(in: notebook.folderID), nil)
        let copy = Notebook(title: notebook.title + copySuffix, kind: notebook.kind, folderID: notebook.folderID,
                            cover: notebook.cover, template: notebook.template, paperSize: notebook.paperSizeValue,
                            orientation: notebook.orientationValue, paperColor: notebook.paperColorValue, sortKey: key, now: now)
        copy.scrollDirection = notebook.scrollDirection
        copy.richText = notebook.richText
        copy.pdfOutlineImported = notebook.pdfOutlineImported
        context.insert(copy)
        let nid = notebook.id
        let pages = try context.fetch(FetchDescriptor<Page>(predicate: #Predicate { $0.notebookID == nid && $0.deletedAt == nil }))
        var pageMap: [UUID: UUID] = [:]
        for p in pages {
            let np = Page(notebookID: copy.id, sortKey: p.sortKey, size: p.size, isInfinite: p.isInfinite, now: now)
            np.templateOverride = p.templateOverride
            np.paperColorOverride = p.paperColorOverride
            np.backgroundAssetID = p.backgroundAssetID
            np.backgroundPageIndex = p.backgroundPageIndex
            np.inkData = p.inkData
            np.strokeIDs = p.strokeIDs
            np.inkHash = p.inkHash
            np.recognizedText = p.recognizedText
            np.ocrInkHash = p.ocrInkHash
            context.insert(np)
            markDirty(np, fields: Self.pageFields, now: now)
            pageMap[p.id] = np.id
            try duplicateElements(of: p.id, to: np.id, now: now)
        }
        try duplicateBookmarksAndOutline(from: nid, to: copy.id, pageMap: pageMap, now: now)
        markDirty(copy, fields: Self.notebookFields, now: now)
        try context.save()
        return copy
    }

    // MARK: Helpers

    static let notebookFields = ["title", "kind", "folderID", "coverSpec", "defaultTemplate", "paperSize", "orientation",
                                 "paperColor", "scrollDirection", "isFavorite", "isLocked", "sortKey", "richText"]
    static let pageFields = ["notebookID", "sortKey", "widthPts", "heightPts", "templateOverride", "backgroundAssetID",
                             "backgroundPageIndex", "inkData", "strokeIDs", "inkHash", "recognizedText", "ocrInkHash", "isInfinite"]

    private func duplicateElements(of pageID: UUID, to newPageID: UUID, now: Date) throws {
        let rows = try context.fetch(FetchDescriptor<PageElement>(predicate: #Predicate { $0.pageID == pageID && $0.deletedAt == nil }))
        for row in rows {
            var v = row.value
            v.id = UUID()
            v.pageID = newPageID
            let copy = PageElement(value: v, now: now)
            context.insert(copy)
            markDirty(copy, fields: ["kind", "x", "y", "width", "height", "rotation", "zIndex", "payload", "assetID", "pageID"], now: now)
        }
    }

    private func duplicateBookmarksAndOutline(from nid: UUID, to newID: UUID, pageMap: [UUID: UUID], now: Date) throws {
        let marks = try context.fetch(FetchDescriptor<Bookmark>(predicate: #Predicate { $0.notebookID == nid && $0.deletedAt == nil }))
        for b in marks {
            guard let mapped = pageMap[b.pageID] else { continue }
            let copy = Bookmark(notebookID: newID, pageID: mapped, title: b.title, now: now)
            context.insert(copy)
            markDirty(copy, fields: ["notebookID", "pageID", "title"], now: now)
        }
        let entries = try context.fetch(FetchDescriptor<OutlineEntry>(predicate: #Predicate { $0.notebookID == nid && $0.deletedAt == nil }))
        var idMap: [UUID: UUID] = [:]
        for e in entries { idMap[e.id] = UUID() }
        for e in entries {
            let copy = OutlineEntry(id: idMap[e.id] ?? UUID(), notebookID: newID, title: e.title,
                                    pageID: e.pageID.flatMap { pageMap[$0] }, pdfPageIndex: e.pdfPageIndex,
                                    parentID: e.parentID.flatMap { idMap[$0] }, sortKey: e.sortKey,
                                    source: OutlineSource(rawValue: e.source) ?? .user, now: now)
            context.insert(copy)
            markDirty(copy, fields: ["notebookID", "title", "pageID", "pdfPageIndex", "parentID", "sortKey", "source"], now: now)
        }
    }

    private func requireFolder(_ id: UUID) throws -> Folder {
        guard let f = folder(id: id) else { throw StoreError.notFound("the folder") }
        return f
    }

    private func requireNotebook(_ id: UUID) throws -> Notebook {
        guard let n = notebook(id: id) else { throw StoreError.notFound("the notebook") }
        return n
    }

    private func lastNotebookKey(in folder: UUID?) throws -> String? {
        try allNotebooks().filter { $0.deletedAt == nil && $0.folderID == folder }.map(\.sortKey).max()
    }

    private func lastFolderKey(in parent: UUID?) throws -> String? {
        try allFolders().filter { $0.deletedAt == nil && $0.parentID == parent }.map(\.sortKey).max()
    }

    static func subtreeFolders(of id: UUID, in folders: [Folder]) -> [Folder] {
        var result: [Folder] = []
        var queue = [id]
        var seen = Set<UUID>()
        while let next = queue.popLast() {
            guard seen.insert(next).inserted else { continue }
            if let f = folders.first(where: { $0.id == next }) { result.append(f) }
            queue.append(contentsOf: folders.filter { $0.parentID == next }.map(\.id))
        }
        return result
    }

    static func isFolder(_ candidate: UUID, insideOrEqualTo ancestor: UUID, in folders: [Folder]) -> Bool {
        subtreeFolders(of: ancestor, in: folders).contains { $0.id == candidate }
    }

    static func isLive(folderID: UUID, in folders: [Folder]) -> Bool {
        folders.first { $0.id == folderID }.map { $0.deletedAt == nil } ?? false
    }
}
