import Foundation
import SwiftData

/// Outline entries of a notebook: the user's own and the ones imported from a PDF.
/// Removing an entry keeps its children (they move up one level); nothing is deleted for good.
@MainActor
public final class OutlineStore {
    private let context: ModelContext

    public init(context: ModelContext) { self.context = context }

    public func items(in notebookID: UUID, source: OutlineSource? = nil) throws -> [OutlineItem] {
        let rows = try context.fetch(FetchDescriptor<OutlineEntry>(
            predicate: #Predicate { $0.notebookID == notebookID && $0.deletedAt == nil }))
        return rows.map(OutlineItem.init).filter { source == nil || $0.source == source }
    }

    @discardableResult
    public func add(title: String, pageID: UUID, notebookID: UUID, parentID: UUID? = nil, now: Date = .now) throws -> OutlineItem {
        let clean = try requireTitle(title)
        let siblings = try items(in: notebookID, source: .user).filter { $0.parentID == parentID }
        let key = SortKey.between(siblings.map(\.sortKey).max(), nil)
        let row = OutlineEntry(notebookID: notebookID, title: clean, pageID: pageID, parentID: parentID,
                               sortKey: key, source: .user, now: now)
        context.insert(row)
        markDirty(row, fields: Self.fields, now: now)
        try context.save()
        return OutlineItem(row)
    }

    public func rename(id: UUID, to title: String, now: Date = .now) throws {
        let row = try requireRow(id)
        row.title = try requireTitle(title)
        markDirty(row, fields: ["title"], now: now)
        try context.save()
    }

    public func setTarget(id: UUID, pageID: UUID, now: Date = .now) throws {
        let row = try requireRow(id)
        row.pageID = pageID
        markDirty(row, fields: ["pageID"], now: now)
        try context.save()
    }

    public func remove(id: UUID, now: Date = .now) throws {
        let row = try requireRow(id)
        let children = try context.fetch(FetchDescriptor<OutlineEntry>(
            predicate: #Predicate { $0.parentID == id && $0.deletedAt == nil }))
        for child in children {
            child.parentID = row.parentID
            markDirty(child, fields: ["parentID"], now: now)
        }
        row.deletedAt = now
        markDirty(row, fields: ["deletedAt"], now: now)
        try context.save()
    }

    /// Puts an entry under `parentID`, directly before the sibling `beforeID` (or last when nil).
    public func move(id: UUID, toParent parentID: UUID?, before beforeID: UUID?, now: Date = .now) throws {
        let row = try requireRow(id)
        if let parentID {
            let all = try items(in: row.notebookID)
            guard parentID != id, !OutlineTree.descendantIDs(of: id, in: all).contains(parentID) else {
                throw StoreError.invalid("An outline entry can't be moved inside itself.")
            }
        }
        let siblings = try items(in: row.notebookID).filter { $0.parentID == parentID && $0.id != id }
            .sorted { SortKey.areInIncreasingOrder(($0.sortKey, $0.id), ($1.sortKey, $1.id)) }
        var previous = siblings.last
        var next: OutlineItem?
        if let beforeID, let at = siblings.firstIndex(where: { $0.id == beforeID }) {
            next = siblings[at]
            previous = at > 0 ? siblings[at - 1] : nil
        }
        row.parentID = parentID
        row.sortKey = SortKey.between(previous?.sortKey, next?.sortKey)
        markDirty(row, fields: ["parentID", "sortKey"], now: now)
        try context.save()
    }

    // MARK: Helpers

    private static let fields = ["notebookID", "title", "pageID", "pdfPageIndex", "parentID", "sortKey", "source"]

    private func requireTitle(_ title: String) throws -> String {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw StoreError.invalid("An outline entry needs a title.") }
        return clean
    }

    private func requireRow(_ id: UUID) throws -> OutlineEntry {
        guard let row = try context.fetch(FetchDescriptor<OutlineEntry>(predicate: #Predicate { $0.id == id })).first else {
            throw StoreError.notFound("the outline entry")
        }
        return row
    }
}
