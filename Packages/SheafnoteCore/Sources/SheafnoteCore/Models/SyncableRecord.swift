import Foundation
import SwiftData

public extension Notification.Name {
    /// Posted by `markDirty` after any synced record changes. Sync listens.
    static let sheafnoteModelDidChange = Notification.Name("co.xanom.sheafnote.modelDidChange")
}

public protocol SyncableRecord: PersistentModel {
    var id: UUID { get }
    var createdAt: Date { get }
    var modifiedAt: Date { get set }
    var deletedAt: Date? { get set }
    var syncDirty: Bool { get set }
    var dirtyFields: [String] { get set }
    var ckSystemFields: Data? { get set }
    var formatVersion: Int { get }
    static var recordType: String { get }
}

public enum SchemaFormat {
    public static let currentVersion = 1
}

/// Marks a record changed: bumps `modifiedAt`, flags it for sync, unions the changed field names.
public func markDirty<T: SyncableRecord>(_ r: T, fields: [String], now: Date = .now) {
    r.modifiedAt = now
    r.syncDirty = true
    var merged = r.dirtyFields
    for f in fields where !merged.contains(f) { merged.append(f) }
    r.dirtyFields = merged
    NotificationCenter.default.post(name: .sheafnoteModelDidChange, object: nil)
}
