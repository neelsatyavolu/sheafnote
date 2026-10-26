import Foundation
import SwiftData

/// A model that maps to one CloudKit record type. Implemented in `SyncCodable+*.swift`.
///
/// Rules (design 4.2): CloudKit field name = Swift property name; relationships are plain UUID strings;
/// LOCAL ONLY properties (`baseInkData`, `baseStrokeIDs`, `syncDirty`, `dirtyFields`, `ckSystemFields`) never leave the device.
protocol SyncCodable: SyncableRecord {
    var createdAt: Date { get set }
    var formatVersion: Int { get set }

    /// Names of the synced domain fields (everything except the common fields).
    static var domainFields: [String] { get }
    /// Fields a record must carry to be usable (relationship ids). A record missing one is rejected as malformed.
    static var requiredFields: [String] { get }
    func encodeDomain(into bag: inout FieldBag)
    /// Copies the named domain fields from the record into the model. Absent fields become nil / default.
    func assign(_ r: SyncRecord, fields: Set<String>)
    /// A new, not yet inserted model carrying the identity of the record. Fields are assigned afterwards.
    static func blank(id: UUID) -> Self
    /// Concrete key paths for generic fetches. See `SyncKeyPaths`.
    static var syncKeyPaths: SyncKeyPaths<Self> { get }
}

extension SyncCodable {
    static var requiredFields: [String] { [] }
}

extension Page {
    /// Ink payload fields: merged per stroke, never overwritten field by field.
    static let inkFields: Set<String> = ["inkData", "strokeIDs", "inkHash"]
}
