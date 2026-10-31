import CloudKit
import Foundation
import Testing
@testable import SheafnoteCore

@MainActor
@Suite struct CloudKitSchemaTests {
    /// `cloudkit/schema.ckdb` at the repository root, the file imported with `cktool import-schema`.
    private static let schemaFile = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "cloudkit/schema.ckdb")

    @Test func schemaDeclaresExactlyTheSyncedFieldsOfEveryRecordType() {
        #expect(Set(CloudKitSchema.recordTypes.keys) == Set(RecordMapper.recordTypes))
        for recordType in RecordMapper.recordTypes {
            let declared = Set(CloudKitSchema.recordTypes[recordType]?.keys.map { $0 } ?? [])
            #expect(declared == Set(RecordMapper.fieldNames(for: recordType)), "\(recordType)")
        }
    }

    @Test func everyEncodedValueHasItsDeclaredType() throws {
        let fixture = try SyncFixture()
        for key in try fixture.populateEverything() {
            let record = try #require(try RecordMapper.encode(key, in: fixture.context))
            for (name, value) in record.fields {
                let declared = try #require(CloudKitSchema.type(of: name, in: key.recordType), "\(key.recordType).\(name)")
                #expect(Self.allowed(for: value).contains(declared), "\(key.recordType).\(name) is \(declared)")
            }
        }
    }

    /// CloudKit fixes a field's type on first save, so a field must never switch between Bytes and Asset by size.
    @Test func binaryFieldsKeepTheirCloudKitTypeWhateverTheirSize() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "sheafnote-schema-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        for (recordType, fields) in CloudKitSchema.recordTypes {
            for (name, type) in fields where type == .bytes || type == .asset {
                for size in [4, 300_000] {
                    let record = SyncRecord(key: RecordKey(recordType: recordType, id: UUID()),
                                            fields: [name: .bytes(Data(repeating: 7, count: size))])
                    let (ck, _) = try CKRecordBridge.ckRecord(for: record, assetDirectory: dir)
                    #expect((ck[name] is CKAsset) == (type == .asset), "\(recordType).\(name) at \(size) bytes")
                }
            }
        }
    }

    /// Regenerate with `SHEAFNOTE_WRITE_SCHEMA=1 swift test --package-path Packages/SheafnoteCore --filter CloudKitSchemaTests`.
    @Test func checkedInSchemaFileMatchesTheCode() throws {
        if ProcessInfo.processInfo.environment["SHEAFNOTE_WRITE_SCHEMA"] == "1" {
            try CloudKitSchema.ckdb().write(to: Self.schemaFile, atomically: true, encoding: .utf8)
        }
        let onDisk = try String(contentsOf: Self.schemaFile, encoding: .utf8)
        #expect(onDisk == CloudKitSchema.ckdb(), "cloudkit/schema.ckdb is stale: rerun with SHEAFNOTE_WRITE_SCHEMA=1")
    }

    private static func allowed(for value: SyncValue) -> Set<CloudKitSchema.FieldType> {
        switch value {
        case .string: [.string]
        case .int, .bool: [.int64]
        case .double: [.double]
        case .date: [.timestamp]
        case .strings: [.stringList]
        case .bytes: [.bytes, .asset]
        }
    }
}
