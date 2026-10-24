import Foundation
import SwiftData

public struct BookmarkItem: Sendable, Hashable, Identifiable {
    public var id: UUID
    public var pageID: UUID
    public var title: String?
    public var createdAt: Date

    public init(id: UUID, pageID: UUID, title: String?, createdAt: Date) {
        self.id = id
        self.pageID = pageID
        self.title = title
        self.createdAt = createdAt
    }
}

public enum BookmarkOrdering {
    /// Bookmarks follow the order of their pages; bookmarks whose page is gone go last, oldest first.
    public static func sorted(_ items: [BookmarkItem], pageOrder: [UUID]) -> [BookmarkItem] {
        let position = Dictionary(pageOrder.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        return items.sorted { a, b in
            let pa = position[a.pageID] ?? Int.max
            let pb = position[b.pageID] ?? Int.max
            if pa != pb { return pa < pb }
            if a.createdAt != b.createdAt { return a.createdAt < b.createdAt }
            return a.id.uuidString < b.id.uuidString
        }
    }
}

/// Page bookmarks of a notebook. Removing a bookmark is a soft delete, like everything else that syncs.
@MainActor
public final class BookmarkStore {
    private let context: ModelContext

    public init(context: ModelContext) { self.context = context }

    public func bookmarks(in notebookID: UUID, pageOrder: [UUID]) throws -> [BookmarkItem] {
        let rows = try liveRows(in: notebookID)
        let items = rows.map { BookmarkItem(id: $0.id, pageID: $0.pageID, title: $0.title, createdAt: $0.createdAt) }
        return BookmarkOrdering.sorted(items, pageOrder: pageOrder)
    }

    public func isBookmarked(pageID: UUID) throws -> Bool {
        try !context.fetch(FetchDescriptor<Bookmark>(
            predicate: #Predicate { $0.pageID == pageID && $0.deletedAt == nil })).isEmpty
    }

    /// Adds a bookmark or removes the existing one(s). Returns whether the page is bookmarked afterwards.
    @discardableResult
    public func toggle(pageID: UUID, notebookID: UUID, now: Date = .now) throws -> Bool {
        let existing = try context.fetch(FetchDescriptor<Bookmark>(
            predicate: #Predicate { $0.pageID == pageID && $0.deletedAt == nil }))
        if existing.isEmpty {
            let revived = try context.fetch(FetchDescriptor<Bookmark>(predicate: #Predicate { $0.pageID == pageID })).first
            if let revived {
                revived.deletedAt = nil
                markDirty(revived, fields: ["deletedAt"], now: now)
            } else {
                let row = Bookmark(notebookID: notebookID, pageID: pageID, now: now)
                context.insert(row)
                markDirty(row, fields: ["notebookID", "pageID", "title"], now: now)
            }
        } else {
            for row in existing {
                row.deletedAt = now
                markDirty(row, fields: ["deletedAt"], now: now)
            }
        }
        try context.save()
        return existing.isEmpty
    }

    public func rename(id: UUID, to title: String?, now: Date = .now) throws {
        guard let row = try context.fetch(FetchDescriptor<Bookmark>(predicate: #Predicate { $0.id == id })).first else {
            throw StoreError.notFound("the bookmark")
        }
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        row.title = (trimmed?.isEmpty ?? true) ? nil : trimmed
        markDirty(row, fields: ["title"], now: now)
        try context.save()
    }

    public func remove(id: UUID, now: Date = .now) throws {
        guard let row = try context.fetch(FetchDescriptor<Bookmark>(predicate: #Predicate { $0.id == id })).first else { return }
        row.deletedAt = now
        markDirty(row, fields: ["deletedAt"], now: now)
        try context.save()
    }

    private func liveRows(in notebookID: UUID) throws -> [Bookmark] {
        try context.fetch(FetchDescriptor<Bookmark>(
            predicate: #Predicate { $0.notebookID == notebookID && $0.deletedAt == nil }))
    }
}
