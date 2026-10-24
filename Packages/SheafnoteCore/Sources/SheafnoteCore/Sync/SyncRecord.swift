import Foundation

/// One CloudKit-compatible field value. A field that is nil is simply absent from `SyncRecord.fields`.
public enum SyncValue: Hashable, Sendable {
    case string(String)
    case int(Int64)
    case double(Double)
    case date(Date)
    case bool(Bool)
    case bytes(Data)
    case strings([String])
}

/// Identifies a record across devices: type plus record name (`id.uuidString`).
public struct RecordKey: Hashable, Sendable, Codable {
    public let recordType: String
    public let id: UUID

    public init(recordType: String, id: UUID) {
        self.recordType = recordType
        self.id = id
    }

    public var recordName: String { id.uuidString }
}

/// A CloudKit-free snapshot of a record. `RecordMapper` converts models to and from this; `CKRecordBridge`
/// converts it to and from `CKRecord`. The merge and apply logic only ever sees this type, so it is testable
/// without iCloud.
public struct SyncRecord: Hashable, Sendable {
    public var key: RecordKey
    public var fields: [String: SyncValue]
    /// Server change tag of the version this snapshot came from (nil for a record never saved to the server).
    public var changeTag: String?
    /// Opaque archive of the CKRecord system fields (`CKRecord.encodeSystemFields`), needed to save over the server version.
    public var systemFields: Data?

    public init(key: RecordKey, fields: [String: SyncValue] = [:], changeTag: String? = nil, systemFields: Data? = nil) {
        self.key = key
        self.fields = fields
        self.changeTag = changeTag
        self.systemFields = systemFields
    }

    public var recordType: String { key.recordType }
    public var id: UUID { key.id }
}

public enum CommonField {
    public static let formatVersion = "formatVersion"
    public static let createdAt = "createdAt"
    public static let modifiedAt = "modifiedAt"
    public static let deletedAt = "deletedAt"
    public static let all: Set<String> = [formatVersion, createdAt, modifiedAt, deletedAt]
}

public extension SyncRecord {
    func string(_ name: String) -> String? { if case .string(let v) = fields[name] { v } else { nil } }
    func int(_ name: String) -> Int? { if case .int(let v) = fields[name] { Int(v) } else { nil } }
    func double(_ name: String) -> Double? {
        switch fields[name] {
        case .double(let v): v
        case .int(let v): Double(v)
        default: nil
        }
    }

    /// CloudKit has no Bool type, so a Bool arrives as Int64 0/1.
    func bool(_ name: String) -> Bool? {
        switch fields[name] {
        case .bool(let v): v
        case .int(let v): v != 0
        default: nil
        }
    }
    func date(_ name: String) -> Date? { if case .date(let v) = fields[name] { v } else { nil } }
    func bytes(_ name: String) -> Data? { if case .bytes(let v) = fields[name] { v } else { nil } }
    func strings(_ name: String) -> [String]? { if case .strings(let v) = fields[name] { v } else { nil } }
    func uuid(_ name: String) -> UUID? { string(name).flatMap(UUID.init(uuidString:)) }

    /// The record's format version. A missing field means a record written before the field existed: version 1.
    var formatVersion: Int { int(CommonField.formatVersion) ?? 1 }
    var modifiedAt: Date { date(CommonField.modifiedAt) ?? .distantPast }
    var deletedAt: Date? { date(CommonField.deletedAt) }
}

/// Collects optional field values, skipping nils.
struct FieldBag {
    private(set) var fields: [String: SyncValue] = [:]

    mutating func set(_ name: String, _ v: String?) { if let v { fields[name] = .string(v) } }
    mutating func set(_ name: String, _ v: Int?) { if let v { fields[name] = .int(Int64(v)) } }
    mutating func set(_ name: String, _ v: Double?) { if let v { fields[name] = .double(v) } }
    mutating func set(_ name: String, _ v: Bool?) { if let v { fields[name] = .bool(v) } }
    mutating func set(_ name: String, _ v: Date?) { if let v { fields[name] = .date(v) } }
    mutating func set(_ name: String, _ v: Data?) { if let v { fields[name] = .bytes(v) } }
    mutating func set(_ name: String, _ v: [String]) { fields[name] = .strings(v) }
    mutating func set(_ name: String, _ v: UUID?) { if let v { fields[name] = .string(v.uuidString) } }
}
