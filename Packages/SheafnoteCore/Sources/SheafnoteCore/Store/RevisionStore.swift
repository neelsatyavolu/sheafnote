import Foundation
import SwiftData

/// The Recovered area. Local only, never synced. Every destructive page operation snapshots here first.
@MainActor
public final class RevisionStore {
    private let context: ModelContext

    public init(context: ModelContext) { self.context = context }

    @discardableResult
    public func snapshot(page: Page, reason: RevisionReason, note: String? = nil, now: Date = .now) throws -> PageRevision {
        let pageID = page.id
        let elements = try context.fetch(FetchDescriptor<PageElement>(
            predicate: #Predicate { $0.pageID == pageID && $0.deletedAt == nil }))
        let values = elements.map(\.value).sorted { $0.zIndex < $1.zIndex }
        let revision = PageRevision(pageID: page.id, notebookID: page.notebookID, reason: reason, createdAt: now,
                                    inkData: page.inkData, strokeIDs: page.strokeIDs,
                                    elements: JSONCoding.encode(values), note: note)
        context.insert(revision)
        try context.save()
        return revision
    }

    public func revisions(for pageID: UUID) -> [PageRevision] {
        let all = (try? context.fetch(FetchDescriptor<PageRevision>(
            predicate: #Predicate { $0.pageID == pageID }, sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))) ?? []
        return all
    }

    public func allRevisions() throws -> [PageRevision] {
        try context.fetch(FetchDescriptor<PageRevision>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))
    }

    /// Restores as a NEW page right after the original (or at the end if the original is gone). Never overwrites.
    @discardableResult
    public func restore(_ revision: PageRevision, now: Date = .now) throws -> Page {
        let notebookID = revision.notebookID
        let siblings = try context.fetch(FetchDescriptor<Page>(
            predicate: #Predicate { $0.notebookID == notebookID && $0.deletedAt == nil }))
            .sorted { SortKey.areInIncreasingOrder(($0.sortKey, $0.id), ($1.sortKey, $1.id)) }
        let original = siblings.firstIndex { $0.id == revision.pageID }
        let prev = original.map { siblings[$0].sortKey } ?? siblings.last?.sortKey
        let next = original.flatMap { $0 + 1 < siblings.count ? siblings[$0 + 1].sortKey : nil }
        let size = siblings.first { $0.id == revision.pageID }?.size ?? siblings.first?.size ?? PaperSize.a4.portraitSize
        let page = Page(notebookID: notebookID, sortKey: SortKey.between(prev, next), size: size, now: now)
        page.inkData = revision.inkData
        page.strokeIDs = revision.strokeIDs
        page.inkHash = revision.inkData.map { Hashing.sha256Hex($0) } ?? ""
        context.insert(page)
        let values = JSONCoding.decode([ElementValue].self, from: revision.elements) ?? []
        for v in values {
            var copy = v
            copy.id = UUID()
            copy.pageID = page.id
            context.insert(PageElement(value: copy, now: now))
        }
        markDirty(page, fields: ["inkData", "strokeIDs", "inkHash", "sortKey"], now: now)
        try context.save()
        return page
    }

    /// Removes snapshots older than 30 days.
    @discardableResult
    public func purgeExpired(now: Date = .now) throws -> Int {
        let expired = try context.fetch(FetchDescriptor<PageRevision>()).filter { $0.expiresAt < now }
        for r in expired { context.delete(r) }
        if !expired.isEmpty { try context.save() }
        return expired.count
    }
}
