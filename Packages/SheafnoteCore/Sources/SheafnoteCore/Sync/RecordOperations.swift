import Foundation
import SwiftData

/// Type-erased per-record-type operations behind `RecordMapper`.
@MainActor
protocol RecordOperations {
    var recordType: String { get }
    var fieldNames: [String] { get }
    func encode(id: UUID, in context: ModelContext) throws -> SyncRecord?
    func dirtyIDs(in context: ModelContext) throws -> [UUID]
    func allIDs(in context: ModelContext) throws -> [UUID]
    func markAllDirty(in context: ModelContext) throws -> Int
    func applyServer(_ r: SyncRecord, in context: ModelContext, ink: any InkMerging, now: Date, save: Bool) throws -> ApplyOutcome
    func applyServerDeletion(id: UUID, in context: ModelContext, save: Bool) throws -> ApplyOutcome
    func confirmSent(sent: SyncRecord, saved: SyncRecord, in context: ModelContext) throws
    func exists(id: UUID, in context: ModelContext) throws -> Bool
    func forgetServerVersion(id: UUID, in context: ModelContext) throws
}

@MainActor
struct TypedOperations<T: SyncCodable>: RecordOperations {
    var recordType: String { T.recordType }
    var fieldNames: [String] { T.domainFields + CommonField.all.sorted() }

    func find(_ id: UUID, in context: ModelContext) throws -> T? {
        var descriptor = FetchDescriptor<T>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    func encode(id: UUID, in context: ModelContext) throws -> SyncRecord? {
        try find(id, in: context).map(Self.snapshot)
    }

    static func snapshot(_ row: T) -> SyncRecord {
        var bag = FieldBag()
        row.encodeDomain(into: &bag)
        bag.set(CommonField.formatVersion, row.formatVersion)
        bag.set(CommonField.createdAt, row.createdAt)
        bag.set(CommonField.modifiedAt, row.modifiedAt)
        bag.set(CommonField.deletedAt, row.deletedAt)
        return SyncRecord(key: RecordKey(recordType: T.recordType, id: row.id), fields: bag.fields,
                          systemFields: row.ckSystemFields)
    }

    func dirtyIDs(in context: ModelContext) throws -> [UUID] {
        let current = SchemaFormat.currentVersion
        return try context.fetch(FetchDescriptor<T>(predicate: #Predicate { $0.syncDirty == true && $0.formatVersion <= current }))
            .map(\.id)
    }

    func allIDs(in context: ModelContext) throws -> [UUID] {
        let current = SchemaFormat.currentVersion
        return try context.fetch(FetchDescriptor<T>(predicate: #Predicate { $0.formatVersion <= current })).map(\.id)
    }

    func markAllDirty(in context: ModelContext) throws -> Int {
        let rows = try context.fetch(FetchDescriptor<T>())
        for row in rows {
            row.syncDirty = true
            row.ckSystemFields = nil
        }
        return rows.count
    }

    func applyServer(_ r: SyncRecord, in context: ModelContext, ink: any InkMerging, now: Date,
                     save: Bool) throws -> ApplyOutcome {
        for field in T.requiredFields where r.string(field) == nil { return .ignored(.malformed(field: field)) }
        let outcome: ApplyOutcome
        if let row = try find(r.id, in: context) {
            if row.syncDirty {
                outcome = try mergeDirty(row, with: r, ink: ink, in: context, now: now)
            } else {
                adopt(r, into: row, fields: Set(T.domainFields))
                outcome = .updated
            }
        } else {
            let created = T.blank(id: r.id)
            context.insert(created)
            adopt(r, into: created, fields: Set(T.domainFields))
            outcome = .created
        }
        if save { try context.save() }
        return outcome
    }

    /// Takes the server's version of `fields` and marks the row clean.
    private func adopt(_ r: SyncRecord, into row: T, fields: Set<String>) {
        row.assign(r, fields: fields)
        row.createdAt = r.date(CommonField.createdAt) ?? row.createdAt
        row.modifiedAt = r.modifiedAt == .distantPast ? row.modifiedAt : r.modifiedAt
        row.deletedAt = r.deletedAt
        row.formatVersion = r.formatVersion
        row.ckSystemFields = r.systemFields
        row.syncDirty = false
        row.dirtyFields = []
        if let page = row as? Page { page.adoptServerInkAsBase() }
    }

    private func mergeDirty(_ row: T, with r: SyncRecord, ink: any InkMerging, in context: ModelContext,
                            now: Date) throws -> ApplyOutcome {
        let local = LocalRowState(dirtyFields: Set(row.dirtyFields), modifiedAt: row.modifiedAt, deletedAt: row.deletedAt)
        let special = row is Page ? Page.inkFields : []
        if let notebook = row as? Notebook { TextConflictCopy.preserveServerText(for: notebook, server: r, in: context, now: now) }
        let resolution = ConflictResolver.resolve(recordType: T.recordType, domainFields: T.domainFields,
                                                  excluding: special, local: local, server: r)
        row.assign(r, fields: resolution.fieldsFromServer)
        row.deletedAt = resolution.deletedAt
        row.modifiedAt = resolution.modifiedAt
        row.createdAt = r.date(CommonField.createdAt) ?? row.createdAt
        row.formatVersion = max(row.formatVersion, r.formatVersion)
        row.ckSystemFields = r.systemFields
        var remaining = resolution.remainingDirtyFields
        var outcome = ApplyOutcome.merged
        if let page = row as? Page {
            let inkResult = try PageInkConflict.resolve(page, server: r, ink: ink, in: context, now: now)
            if inkResult.inkStillDirty { remaining.formUnion(Page.inkFields) } else { remaining.subtract(Page.inkFields) }
            if let special = inkResult.outcome { outcome = special }
        }
        row.dirtyFields = remaining.sorted()
        row.syncDirty = !remaining.isEmpty
        return outcome
    }

    func applyServerDeletion(id: UUID, in context: ModelContext, save: Bool) throws -> ApplyOutcome {
        guard let row = try find(id, in: context) else { return .deleted }
        let outcome: ApplyOutcome
        if row.deletedAt != nil {
            // Already in Recently Deleted here, and the other device removed it for good.
            context.delete(row)
            outcome = .deleted
        } else {
            // Alive here: never delete a user's live data because the server lost the record. Upload it again.
            row.ckSystemFields = nil
            row.syncDirty = true
            outcome = .resurrected
        }
        if save { try context.save() }
        return outcome
    }

    func confirmSent(sent: SyncRecord, saved: SyncRecord, in context: ModelContext) throws {
        guard let row = try find(sent.id, in: context) else { return }
        row.ckSystemFields = saved.systemFields
        if row.modifiedAt <= sent.modifiedAt {
            row.syncDirty = false
            row.dirtyFields = []
        }
        if let page = row as? Page {
            page.baseInkData = sent.bytes("inkData")
            page.baseStrokeIDs = sent.strings("strokeIDs") ?? []
        }
        try context.save()
    }
}

extension TypedOperations {
    func exists(id: UUID, in context: ModelContext) throws -> Bool { try find(id, in: context) != nil }

    func forgetServerVersion(id: UUID, in context: ModelContext) throws {
        guard let row = try find(id, in: context) else { return }
        row.ckSystemFields = nil
        row.syncDirty = true
    }
}

extension Page {
    /// After taking the server's ink, that version is the base for the next three-way merge.
    func adoptServerInkAsBase() {
        baseInkData = inkData
        baseStrokeIDs = strokeIDs
    }
}
