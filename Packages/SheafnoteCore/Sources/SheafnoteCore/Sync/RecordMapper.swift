import Foundation
import SwiftData

/// Model <-> `SyncRecord` conversion for all 12 synced record types (design 4.2).
/// Everything here runs on the main actor against one `ModelContext`.
@MainActor
public enum RecordMapper {
    /// Every synced record type, in an order where parents tend to precede children (not required for correctness).
    public static let recordTypes: [String] = operations.map(\.recordType)

    static let operations: [any RecordOperations] = [
        TypedOperations<Folder>(), TypedOperations<Notebook>(), TypedOperations<Asset>(), TypedOperations<Page>(),
        TypedOperations<PageElement>(), TypedOperations<OutlineEntry>(), TypedOperations<Bookmark>(),
        TypedOperations<AudioRecording>(), TypedOperations<Flashcard>(), TypedOperations<StudyState>(),
        TypedOperations<SavedElement>(), TypedOperations<AppSetting>(),
    ]

    static func operations(for recordType: String) -> (any RecordOperations)? {
        operations.first { $0.recordType == recordType }
    }

    /// The current local snapshot of a row, or nil if the row no longer exists.
    public static func encode(_ key: RecordKey, in context: ModelContext) throws -> SyncRecord? {
        try operations(for: key.recordType)?.encode(id: key.id, in: context)
    }

    /// Keys of rows with unsent changes, excluding rows written by a newer app version (those are read-only here).
    public static func dirtyKeys(in context: ModelContext) throws -> [RecordKey] {
        try operations.flatMap { ops in
            try ops.dirtyIDs(in: context).map { RecordKey(recordType: ops.recordType, id: $0) }
        }
    }

    public static func allKeys(in context: ModelContext) throws -> [RecordKey] {
        try operations.flatMap { ops in
            try ops.allIDs(in: context).map { RecordKey(recordType: ops.recordType, id: $0) }
        }
    }

    /// Flags every row (including soft-deleted ones) as unsent and forgets server system fields,
    /// so the next sync uploads the full local library to whichever account is signed in.
    @discardableResult
    public static func markAllDirty(in context: ModelContext) throws -> Int {
        let count = try operations.reduce(0) { try $0 + $1.markAllDirty(in: context) }
        try context.save()
        return count
    }

    /// Applies a record fetched from the server. Never throws for bad records (they are reported as ignored).
    public static func applyServer(_ record: SyncRecord, in context: ModelContext, ink: any InkMerging,
                                   now: Date = .now) throws -> ApplyOutcome {
        guard let ops = operations(for: record.recordType) else { return .ignored(.unknownRecordType) }
        return try ops.applyServer(record, in: context, ink: ink, now: now)
    }

    /// The server deleted a record (another device purged it for good).
    public static func applyServerDeletion(_ key: RecordKey, in context: ModelContext) throws -> ApplyOutcome {
        guard let ops = operations(for: key.recordType) else { return .ignored(.unknownRecordType) }
        return try ops.applyServerDeletion(id: key.id, in: context)
    }

    /// The server accepted our record. Clears the dirty flag unless the row changed again while the send was in flight.
    public static func confirmSent(sent: SyncRecord, saved: SyncRecord, in context: ModelContext) throws {
        try operations(for: sent.recordType)?.confirmSent(sent: sent, saved: saved, in: context)
    }

    /// Row is waiting for an app update (written by a newer format version): never upload edits over it.
    public static func isReadOnlyFromNewerVersion(_ record: some SyncableRecord) -> Bool {
        record.formatVersion > SchemaFormat.currentVersion
    }
}

public enum IgnoredReason: Sendable, Equatable {
    case unknownRecordType
    case malformed(field: String)
}

public enum ApplyOutcome: Sendable, Equatable {
    case created, updated
    /// Local unsent changes and the server version were combined.
    case merged
    /// Page ink could not be merged; ours stays live and theirs went to the Recovered area.
    case keptBothVersions
    case deleted
    /// The server deleted a row that is alive here; it will be uploaded again.
    case resurrected
    case ignored(IgnoredReason)
}
