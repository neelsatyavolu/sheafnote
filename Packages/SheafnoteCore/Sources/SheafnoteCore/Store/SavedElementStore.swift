import Foundation
import SwiftData

public struct SavedElementRecord: Identifiable, Sendable, Hashable {
    public var id: UUID
    public var name: String
    public var category: String
    public var size: CGSize
    public var thumbnail: Data
    public var inkData: Data?
    public var elements: [ElementValue]
}

/// Persistence for the saved-elements library ("Save as element"). Insertion into pages is done in the app.
@MainActor
public final class SavedElementStore {
    private let context: ModelContext

    public init(context: ModelContext) { self.context = context }

    public func all() throws -> [SavedElementRecord] {
        try context.fetch(FetchDescriptor<SavedElement>(
            predicate: #Predicate { $0.deletedAt == nil }, sortBy: [SortDescriptor(\.createdAt)])).map(Self.record)
    }

    @discardableResult
    public func save(name: String, category: String, size: CGSize, inkData: Data?, elements: [ElementValue],
                     thumbnail: Data, now: Date = .now) throws -> SavedElementRecord {
        let row = SavedElement(name: name, category: category, width: Double(size.width), height: Double(size.height),
                               inkData: inkData, elements: JSONCoding.encode(elements), thumbnail: thumbnail, now: now)
        context.insert(row)
        markDirty(row, fields: ["name", "category", "width", "height", "inkData", "elements", "thumbnail"], now: now)
        try context.save()
        return Self.record(row)
    }

    public func rename(id: UUID, to name: String, now: Date = .now) throws {
        let row = try require(id)
        row.name = name
        markDirty(row, fields: ["name"], now: now)
        try context.save()
    }

    /// Soft delete (synced tombstone); purged after 30 days.
    public func delete(id: UUID, now: Date = .now) throws {
        let row = try require(id)
        row.deletedAt = now
        markDirty(row, fields: ["deletedAt"], now: now)
        try context.save()
    }

    private func require(_ id: UUID) throws -> SavedElement {
        guard let row = try context.fetch(FetchDescriptor<SavedElement>(predicate: #Predicate { $0.id == id })).first
        else { throw StoreError.notFound("the saved element") }
        return row
    }

    private static func record(_ row: SavedElement) -> SavedElementRecord {
        SavedElementRecord(id: row.id, name: row.name, category: row.category,
                           size: CGSize(width: row.width, height: row.height), thumbnail: row.thumbnail,
                           inkData: row.inkData, elements: JSONCoding.decode([ElementValue].self, from: row.elements) ?? [])
    }
}
