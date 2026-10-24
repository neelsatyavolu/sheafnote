import Foundation
import SwiftData

/// A page version kept in the Recovered area, as shown in Settings.
public struct RecoveredItem: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let pageID: UUID
    public let notebookID: UUID
    public let notebookTitle: String?
    public let reason: RevisionReason
    public let createdAt: Date
    public let expiresAt: Date
    public let strokeCount: Int
    public let note: String?
    /// False once the page the version belonged to no longer exists here.
    public let pageStillExists: Bool
}

/// Lists, restores and deletes `PageRevision`s (conflict copies and pre-delete snapshots). Local only.
/// Restoring always creates a new page; nothing is ever overwritten. Deleting a version is an explicit user action.
@MainActor
public struct RecoveredArea {
    private let context: ModelContext
    private let revisions: RevisionStore

    public init(context: ModelContext) {
        self.context = context
        self.revisions = RevisionStore(context: context)
    }

    public func items(now: Date = .now) throws -> [RecoveredItem] {
        let all = try revisions.allRevisions().filter { $0.expiresAt >= now }
        let notebooks = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<Notebook>()).map { ($0.id, $0.title) })
        let pageIDs = Set(try context.fetch(FetchDescriptor<Page>()).filter { $0.deletedAt == nil }.map(\.id))
        return all.map { r in
            RecoveredItem(id: r.id, pageID: r.pageID, notebookID: r.notebookID, notebookTitle: notebooks[r.notebookID],
                          reason: r.reasonValue, createdAt: r.createdAt, expiresAt: r.expiresAt,
                          strokeCount: r.strokeIDs.count, note: r.note, pageStillExists: pageIDs.contains(r.pageID))
        }
    }

    /// Restores as a new page after the original (or at the end of the notebook).
    @discardableResult
    public func restore(_ id: UUID, now: Date = .now) throws -> Page {
        try revisions.restore(try revision(id), now: now)
    }

    /// Permanently removes one recovered version. Call only after the user confirmed.
    public func delete(_ id: UUID) throws {
        context.delete(try revision(id))
        try context.save()
    }

    /// Removes versions past their 30 days.
    @discardableResult
    public func purgeExpired(now: Date = .now) throws -> Int { try revisions.purgeExpired(now: now) }

    private func revision(_ id: UUID) throws -> PageRevision {
        var descriptor = FetchDescriptor<PageRevision>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let found = try context.fetch(descriptor).first else {
            throw StoreError.notFound("that recovered page")
        }
        return found
    }
}
