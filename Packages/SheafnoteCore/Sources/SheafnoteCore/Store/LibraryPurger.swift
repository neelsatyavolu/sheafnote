import Foundation
import SwiftData

/// Hard-deletes rows. Only used by the 30-day purge and by "Delete Permanently" on items already in the trash.
@MainActor
struct LibraryPurger {
    struct Result {
        var records: [PurgedRecord] = []
        var libraryItems = 0
    }

    let context: ModelContext

    func purge(olderThan cutoff: Date) throws -> Result {
        var result = Result()
        let folders = try context.fetch(FetchDescriptor<Folder>(predicate: #Predicate { $0.deletedAt != nil }))
        let notebooks = try context.fetch(FetchDescriptor<Notebook>(predicate: #Predicate { $0.deletedAt != nil }))
        for n in notebooks where (n.deletedAt ?? .distantFuture) < cutoff { try erase(notebook: n, into: &result) }
        for f in folders where (f.deletedAt ?? .distantFuture) < cutoff {
            result.records.append(PurgedRecord(recordType: Folder.recordType, id: f.id))
            result.libraryItems += 1
            context.delete(f)
        }
        try purgeLooseRows(olderThan: cutoff, into: &result)
        try context.save()
        return result
    }

    func erase(_ items: [LibraryItemRef]) throws -> Result {
        var result = Result()
        for item in items {
            switch item {
            case .notebook(let id):
                guard let n = try context.fetch(FetchDescriptor<Notebook>(predicate: #Predicate { $0.id == id })).first else { continue }
                guard n.deletedAt != nil else { throw StoreError.invalid("Only items in Recently Deleted can be deleted permanently.") }
                try erase(notebook: n, into: &result)
            case .folder(let id):
                guard let f = try context.fetch(FetchDescriptor<Folder>(predicate: #Predicate { $0.id == id })).first else { continue }
                guard f.deletedAt != nil else { throw StoreError.invalid("Only items in Recently Deleted can be deleted permanently.") }
                try erase(folder: f, into: &result)
            }
        }
        try context.save()
        return result
    }

    private func erase(folder: Folder, into result: inout Result) throws {
        let all = try context.fetch(FetchDescriptor<Folder>())
        let subtree = LibraryStore.subtreeFolders(of: folder.id, in: all)
        let ids = Set(subtree.map(\.id))
        let notebooks = try context.fetch(FetchDescriptor<Notebook>()).filter { $0.folderID.map(ids.contains) == true }
        for n in notebooks { try erase(notebook: n, into: &result) }
        for f in subtree {
            result.records.append(PurgedRecord(recordType: Folder.recordType, id: f.id))
            result.libraryItems += 1
            context.delete(f)
        }
    }

    private func erase(notebook n: Notebook, into result: inout Result) throws {
        let nid = n.id
        let pages = try context.fetch(FetchDescriptor<Page>(predicate: #Predicate { $0.notebookID == nid }))
        let pageIDs = Set(pages.map(\.id))
        let elements = try context.fetch(FetchDescriptor<PageElement>()).filter { pageIDs.contains($0.pageID) }
        let audio = try context.fetch(FetchDescriptor<AudioRecording>(predicate: #Predicate { $0.notebookID == nid }))
        let cards = try context.fetch(FetchDescriptor<Flashcard>(predicate: #Predicate { $0.notebookID == nid }))
        let cardIDs = Set(cards.map(\.id))
        let states = try context.fetch(FetchDescriptor<StudyState>()).filter { cardIDs.contains($0.flashcardID) }
        let bookmarks = try context.fetch(FetchDescriptor<Bookmark>(predicate: #Predicate { $0.notebookID == nid }))
        let outline = try context.fetch(FetchDescriptor<OutlineEntry>(predicate: #Predicate { $0.notebookID == nid }))

        var assetIDs = Set(pages.compactMap(\.backgroundAssetID))
        assetIDs.formUnion(elements.compactMap(\.assetID))
        assetIDs.formUnion(audio.map(\.assetID))

        func drop<T: SyncableRecord>(_ rows: [T]) {
            for r in rows { result.records.append(PurgedRecord(recordType: T.recordType, id: r.id)); context.delete(r) }
        }
        drop(states); drop(cards); drop(audio); drop(bookmarks); drop(outline); drop(elements); drop(pages)
        result.records.append(PurgedRecord(recordType: Notebook.recordType, id: n.id))
        result.libraryItems += 1
        context.delete(n)
        try context.save()
        try dropOrphans(among: assetIDs, into: &result)
    }

    /// Assets nothing references any more.
    private func dropOrphans(among ids: Set<UUID>, into result: inout Result) throws {
        guard !ids.isEmpty else { return }
        let used = try AssetReferences.allReferenced(in: context)
        for id in ids.subtracting(used) {
            if let a = try context.fetch(FetchDescriptor<Asset>(predicate: #Predicate { $0.id == id })).first {
                result.records.append(PurgedRecord(recordType: Asset.recordType, id: a.id))
                context.delete(a)
            }
        }
    }

    /// Soft-deleted pages, elements, bookmarks etc. past retention (the notebook itself is still alive).
    private func purgeLooseRows(olderThan cutoff: Date, into result: inout Result) throws {
        func old<T: SyncableRecord>(_ rows: [T]) -> [T] { rows.filter { ($0.deletedAt ?? .distantFuture) < cutoff } }
        func drop<T: SyncableRecord>(_ rows: [T]) {
            for r in old(rows) { result.records.append(PurgedRecord(recordType: T.recordType, id: r.id)); context.delete(r) }
        }
        let pages = old(try context.fetch(FetchDescriptor<Page>(predicate: #Predicate { $0.deletedAt != nil })))
        var assetIDs = Set(pages.compactMap(\.backgroundAssetID))
        // Elements, bookmarks and outline entries of a purged page have no page left to point at: erase them too.
        let pageIDs = Set(pages.map(\.id))
        let orphanElements = pageIDs.isEmpty ? [] : try context.fetch(FetchDescriptor<PageElement>()).filter { pageIDs.contains($0.pageID) }
        let orphanBookmarks = pageIDs.isEmpty ? [] : try context.fetch(FetchDescriptor<Bookmark>()).filter { pageIDs.contains($0.pageID) }
        let orphanOutline = pageIDs.isEmpty ? [] : try context.fetch(FetchDescriptor<OutlineEntry>())
            .filter { $0.pageID.map(pageIDs.contains) == true }
        assetIDs.formUnion(orphanElements.compactMap(\.assetID))
        func dropNow<T: SyncableRecord>(_ rows: [T]) {
            for r in rows { result.records.append(PurgedRecord(recordType: T.recordType, id: r.id)); context.delete(r) }
        }
        dropNow(orphanElements); dropNow(orphanBookmarks); dropNow(orphanOutline)
        drop(pages)
        try context.save()
        drop(try context.fetch(FetchDescriptor<PageElement>(predicate: #Predicate { $0.deletedAt != nil })))
        drop(try context.fetch(FetchDescriptor<Bookmark>(predicate: #Predicate { $0.deletedAt != nil })))
        drop(try context.fetch(FetchDescriptor<OutlineEntry>(predicate: #Predicate { $0.deletedAt != nil })))
        drop(try context.fetch(FetchDescriptor<AudioRecording>(predicate: #Predicate { $0.deletedAt != nil })))
        drop(try context.fetch(FetchDescriptor<Flashcard>(predicate: #Predicate { $0.deletedAt != nil })))
        drop(try context.fetch(FetchDescriptor<StudyState>(predicate: #Predicate { $0.deletedAt != nil })))
        drop(try context.fetch(FetchDescriptor<SavedElement>(predicate: #Predicate { $0.deletedAt != nil })))
        try context.save()
        try dropOrphans(among: assetIDs, into: &result)
    }
}
