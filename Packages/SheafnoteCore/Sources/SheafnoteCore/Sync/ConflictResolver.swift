import Foundation

/// What we know about a local row that has unsent changes when a server version arrives.
public struct LocalRowState: Sendable, Equatable {
    public var dirtyFields: Set<String>
    public var modifiedAt: Date
    public var deletedAt: Date?

    public init(dirtyFields: Set<String>, modifiedAt: Date, deletedAt: Date?) {
        self.dirtyFields = dirtyFields
        self.modifiedAt = modifiedAt
        self.deletedAt = deletedAt
    }
}

public struct ConflictResolution: Sendable, Equatable {
    /// Domain fields to overwrite with the server's value. Every other domain field keeps our value.
    public var fieldsFromServer: Set<String>
    public var deletedAt: Date?
    public var modifiedAt: Date
    /// Fields we still have to send (our value differs from, or was never seen by, the server).
    public var remainingDirtyFields: Set<String>
}

/// Field-level conflict rules for every record except the ink of a page (design 4.3, rule 4):
/// - a field we changed locally keeps our value, every other field takes the server's;
/// - `deletedAt` set on either side wins over edits (delete is a tombstone), but a restore
///   (`deletedAt = nil`) made after the delete wins;
/// - page elements are last-writer-wins per record by `modifiedAt`.
public enum ConflictResolver {
    public static func resolve(recordType: String, domainFields: [String], excluding special: Set<String> = [],
                               local: LocalRowState, server: SyncRecord) -> ConflictResolution {
        let deletion = resolveDeletion(local: local, server: server)
        let candidates = Set(domainFields).subtracting(special)
        let fromServer: Set<String>
        var remaining: Set<String>
        if usesLastWriterWins(recordType) {
            let serverNewer = server.modifiedAt >= local.modifiedAt
            fromServer = serverNewer ? candidates : []
            remaining = serverNewer ? [] : local.dirtyFields.intersection(candidates)
        } else {
            fromServer = candidates.subtracting(local.dirtyFields)
            remaining = local.dirtyFields.intersection(candidates)
        }
        remaining.formUnion(local.dirtyFields.intersection(special))
        if deletion != server.deletedAt { remaining.insert(CommonField.deletedAt) }
        return ConflictResolution(fieldsFromServer: fromServer, deletedAt: deletion,
                                  modifiedAt: max(local.modifiedAt, server.modifiedAt), remainingDirtyFields: remaining)
    }

    public static func usesLastWriterWins(_ recordType: String) -> Bool { recordType == PageElement.recordType }

    static func resolveDeletion(local: LocalRowState, server: SyncRecord) -> Date? {
        let deletionIsLocalChange = local.dirtyFields.contains(CommonField.deletedAt)
        switch (local.deletedAt, server.deletedAt) {
        case (nil, nil):
            return nil
        case let (l?, s?):
            return max(l, s)
        case let (l?, nil):
            // We deleted and the server has not seen it: delete wins over the server's edits.
            // If the delete was already synced, the other device restored the row: restore wins.
            return deletionIsLocalChange ? l : nil
        case let (nil, s?):
            // We restored locally: the restore wins only if it happened after the delete.
            return deletionIsLocalChange && local.modifiedAt > s ? nil : s
        }
    }
}
