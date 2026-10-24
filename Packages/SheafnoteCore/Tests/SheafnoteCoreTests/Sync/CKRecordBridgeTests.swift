import CloudKit
import Foundation
import SwiftData
import Testing
@testable import SheafnoteCore

@MainActor
@Suite struct CKRecordBridgeTests {
    private func tempDir() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "sheafnote-bridge-\(UUID().uuidString)")
    }

    @Test func everyRecordTypeSurvivesTheCloudKitRoundTrip() throws {
        let a = try SyncFixture()
        let keys = try a.populateEverything()
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let b = try SyncFixture()
        for key in keys {
            let original = try #require(try RecordMapper.encode(key, in: a.context))
            let (ck, _) = try CKRecordBridge.ckRecord(for: original, assetDirectory: dir)
            #expect(ck.recordID.zoneID == CKRecordBridge.zoneID && ck.recordType == key.recordType)
            let read = try #require(try CKRecordBridge.syncRecord(from: ck))
            #expect(try RecordMapper.applyServer(read, in: b.context, ink: JSONInkMerging()) == .created, "\(key.recordType)")
        }
        for key in keys {
            let before = try #require(try RecordMapper.encode(key, in: a.context))
            let after = try #require(try RecordMapper.encode(key, in: b.context))
            #expect(before.fields == after.fields, "\(key.recordType)")
        }
    }

    @Test func largeBinaryFieldsBecomeAssetsAndSmallOnesStayInline() throws {
        let a = try SyncFixture()
        let keys = try a.populateEverything()
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let asset = try #require(keys.first { $0.recordType == "SNAsset" })
        let big = try #require(try RecordMapper.encode(asset, in: a.context))
        let (ckBig, files) = try CKRecordBridge.ckRecord(for: big, assetDirectory: dir)
        #expect(ckBig["data"] is CKAsset && files.count == 1)
        #expect(files.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
        let inked = try keys.filter { $0.recordType == "SNPage" }.compactMap { try RecordMapper.encode($0, in: a.context) }
        let ink = try #require(inked.first { $0.bytes("inkData") != nil })
        let (ckPage, _) = try CKRecordBridge.ckRecord(for: ink, assetDirectory: dir)
        #expect(ckPage["inkData"] is CKAsset)          // page ink is always an asset
        let nb = try #require(keys.first { $0.recordType == "SNNotebook" })
        let (ckNb, _) = try CKRecordBridge.ckRecord(for: try #require(try RecordMapper.encode(nb, in: a.context)), assetDirectory: dir)
        #expect(ckNb["richText"] is Data || ckNb["richText"] is NSData)
    }

    @Test func systemFieldsRoundTripSoSavesTargetTheServerVersion() throws {
        let id = UUID()
        let key = RecordKey(recordType: "SNFolder", id: id)
        let server = CKRecord(recordType: "SNFolder", recordID: CKRecordBridge.recordID(for: key))
        server["name"] = "Server" as NSString
        let read = try #require(try CKRecordBridge.syncRecord(from: server))
        #expect(read.systemFields != nil && read.string("name") == "Server")
        let (rebuilt, _) = try CKRecordBridge.ckRecord(for: read, assetDirectory: tempDir())
        #expect(rebuilt.recordID == server.recordID && rebuilt.recordType == "SNFolder")
    }

    @Test func staleSystemFieldsForAnotherRecordAreNotReused() throws {
        let one = RecordKey(recordType: "SNFolder", id: UUID())
        let two = RecordKey(recordType: "SNFolder", id: UUID())
        let ck = CKRecord(recordType: "SNFolder", recordID: CKRecordBridge.recordID(for: one))
        var record = SyncRecord(key: two, fields: ["name": .string("x")], systemFields: CKRecordBridge.encodeSystemFields(ck))
        record.fields["formatVersion"] = .int(1)
        let (built, _) = try CKRecordBridge.ckRecord(for: record, assetDirectory: tempDir())
        #expect(built.recordID.recordName == two.recordName)
    }

    @Test func fieldsThatBecameNilAreClearedOnTheRecord() throws {
        let key = RecordKey(recordType: "SNFolder", id: UUID())
        let record = SyncRecord(key: key, fields: ["name": .string("Only name")])
        let (ck, _) = try CKRecordBridge.ckRecord(for: record, assetDirectory: tempDir())
        #expect(ck["colorName"] == nil && ck["deletedAt"] == nil)
        #expect((ck["name"] as? String) == "Only name")
    }

    @Test func booleansTravelAsIntegersAndReadBackAsBooleans() throws {
        let key = RecordKey(recordType: "SNFolder", id: UUID())
        let record = SyncRecord(key: key, fields: ["isFavorite": .bool(true)])
        let (ck, _) = try CKRecordBridge.ckRecord(for: record, assetDirectory: tempDir())
        let read = try #require(try CKRecordBridge.syncRecord(from: ck))
        #expect(read.bool("isFavorite") == true)
    }

    @Test func unknownFieldTypesAreSkippedOnRead() throws {
        let key = RecordKey(recordType: "SNFolder", id: UUID())
        let ck = CKRecord(recordType: "SNFolder", recordID: CKRecordBridge.recordID(for: key))
        ck["name"] = "ok" as NSString
        ck["location"] = CLLocation(latitude: 1, longitude: 2)
        let read = try #require(try CKRecordBridge.syncRecord(from: ck))
        #expect(read.string("name") == "ok" && read.fields["location"] == nil)
    }

    @Test func recordWithANonUUIDNameIsIgnored() throws {
        let ck = CKRecord(recordType: "SNFolder", recordID: CKRecord.ID(recordName: "not-a-uuid", zoneID: CKRecordBridge.zoneID))
        #expect(try CKRecordBridge.syncRecord(from: ck) == nil)
    }
}
