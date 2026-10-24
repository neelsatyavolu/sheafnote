import CloudKit
import Foundation

public enum CKRecordBridgeError: LocalizedError {
    case unreadableAsset(field: String, underlying: String)

    public var errorDescription: String? {
        switch self {
        case .unreadableAsset(let field, let underlying):
            "A synced file (\(field)) could not be read from iCloud's download. \(underlying)"
        }
    }
}

/// `SyncRecord` <-> `CKRecord`. Types follow design 4.2: strings, dates and lists map directly, `Int`/`Bool` are
/// Int64, `Double` is Double, small `Data` is Bytes, and large `Data` is a `CKAsset` backed by a temp file.
public enum CKRecordBridge {
    public static let zoneName = "SheafnoteZone"
    public static let zoneID = CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)
    /// Binary fields larger than this go out as `CKAsset` (also always for these fields, whatever their size).
    public static let assetThreshold = 100_000
    static let alwaysAsset: Set<String> = ["SNPage.inkData", "SNAsset.data"]

    public static func recordID(for key: RecordKey) -> CKRecord.ID {
        CKRecord.ID(recordName: key.recordName, zoneID: zoneID)
    }

    public static func key(for record: CKRecord) -> RecordKey? {
        UUID(uuidString: record.recordID.recordName).map { RecordKey(recordType: record.recordType, id: $0) }
    }

    /// Builds the record to save. Starts from the stored system fields (so CloudKit sees the version we based the
    /// change on), sets every field we know, clears known fields that are nil now, and leaves unknown fields
    /// (written by a newer app version) untouched. Asset files are written under `assetDirectory`;
    /// the returned URLs must be deleted after the send.
    @MainActor
    public static func ckRecord(for record: SyncRecord, assetDirectory: URL) throws -> (record: CKRecord, tempFiles: [URL]) {
        let ck = decodeSystemFields(record.systemFields, expecting: record.key)
            ?? CKRecord(recordType: record.recordType, recordID: recordID(for: record.key))
        var tempFiles: [URL] = []
        for name in RecordMapper.fieldNames(for: record.recordType) where record.fields[name] == nil {
            ck[name] = nil
        }
        for (name, value) in record.fields {
            switch value {
            case .string(let v): ck[name] = v as NSString
            case .int(let v): ck[name] = NSNumber(value: v)
            case .double(let v): ck[name] = NSNumber(value: v)
            case .bool(let v): ck[name] = NSNumber(value: v ? Int64(1) : Int64(0))
            case .date(let v): ck[name] = v as NSDate
            case .strings(let v): ck[name] = v as NSArray
            case .bytes(let data):
                if data.count > assetThreshold || alwaysAsset.contains("\(record.recordType).\(name)") {
                    let url = try writeAsset(data, in: assetDirectory)
                    tempFiles.append(url)
                    ck[name] = CKAsset(fileURL: url)
                } else {
                    ck[name] = data as NSData
                }
            }
        }
        return (ck, tempFiles)
    }

    /// Reads a fetched record. Unknown field types are skipped; an unreadable asset throws (never silently dropped).
    public static func syncRecord(from ck: CKRecord) throws -> SyncRecord? {
        guard let key = key(for: ck) else { return nil }
        var fields: [String: SyncValue] = [:]
        for name in ck.allKeys() {
            switch ck[name] {
            case let v as String: fields[name] = .string(v)
            case let v as Date: fields[name] = .date(v)
            case let v as Data: fields[name] = .bytes(v)
            case let v as [String]: fields[name] = .strings(v)
            case let v as NSNumber: fields[name] = number(v)
            case let v as CKAsset: fields[name] = .bytes(try read(v, field: name))
            default: continue
            }
        }
        return SyncRecord(key: key, fields: fields, changeTag: ck.recordChangeTag, systemFields: encodeSystemFields(ck))
    }

    public static func encodeSystemFields(_ ck: CKRecord) -> Data {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        ck.encodeSystemFields(with: coder)
        coder.finishEncoding()
        return coder.encodedData
    }

    static func decodeSystemFields(_ data: Data?, expecting key: RecordKey) -> CKRecord? {
        guard let data, let coder = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        coder.requiresSecureCoding = true
        let record = CKRecord(coder: coder)
        coder.finishDecoding()
        guard let record, record.recordID.recordName == key.recordName, record.recordType == key.recordType else { return nil }
        return record
    }

    private static func number(_ n: NSNumber) -> SyncValue {
        CFNumberIsFloatType(n) ? .double(n.doubleValue) : .int(n.int64Value)
    }

    private static func read(_ asset: CKAsset, field: String) throws -> Data {
        guard let url = asset.fileURL else {
            throw CKRecordBridgeError.unreadableAsset(field: field, underlying: "iCloud did not provide the downloaded file.")
        }
        do { return try Data(contentsOf: url) } catch {
            throw CKRecordBridgeError.unreadableAsset(field: field, underlying: error.localizedDescription)
        }
    }

    private static func writeAsset(_ data: Data, in directory: URL) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: UUID().uuidString)
        try data.write(to: url, options: .atomic)
        return url
    }
}
