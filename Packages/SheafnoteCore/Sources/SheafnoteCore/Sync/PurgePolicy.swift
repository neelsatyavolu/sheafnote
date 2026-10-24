import Foundation

/// Soft deletes sync as tombstones (`deletedAt`). Only after 30 days is a row removed for good, and only then
/// is the CloudKit record deleted.
public enum PurgePolicy {
    public static let retention: TimeInterval = Retention.seconds

    /// Rows soft-deleted before this moment may be purged.
    public static func cutoff(now: Date) -> Date { now.addingTimeInterval(-retention) }

    /// True once a tombstone is older than the retention window. A live row (`deletedAt == nil`) never expires.
    public static func isExpired(deletedAt: Date?, now: Date) -> Bool {
        guard let deletedAt else { return false }
        return deletedAt < cutoff(now: now)
    }

    /// Adds purged rows to the queue of CloudKit deletions, without duplicates, keeping order.
    public static func queueDeletions(existing: [RecordKey], purged: [PurgedRecord]) -> [RecordKey] {
        var seen = Set(existing)
        var result = existing
        for p in purged {
            let key = RecordKey(recordType: p.recordType, id: p.id)
            if seen.insert(key).inserted { result.append(key) }
        }
        return result
    }

    /// A queued deletion must not remove a record whose row exists again locally (for example restored from an
    /// archive with the same id): those rows win and are uploaded instead.
    public static func filterRecreated(_ queue: [RecordKey], existing: Set<RecordKey>) -> [RecordKey] {
        queue.filter { !existing.contains($0) }
    }
}
