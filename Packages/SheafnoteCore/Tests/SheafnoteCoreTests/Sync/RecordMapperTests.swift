import Foundation
import SwiftData
import Testing
@testable import SheafnoteCore

@MainActor
@Suite struct RecordMapperTests {
    @Test func coversAllTwelveRecordTypesWithSNPrefix() {
        #expect(RecordMapper.recordTypes.count == 12)
        #expect(Set(RecordMapper.recordTypes).count == 12)
        #expect(RecordMapper.recordTypes.allSatisfy { $0.hasPrefix("SN") })
        #expect(Set(RecordMapper.recordTypes) == ["SNFolder", "SNNotebook", "SNPage", "SNPageElement", "SNAsset",
                                                  "SNOutlineEntry", "SNBookmark", "SNAudioRecording", "SNFlashcard",
                                                  "SNStudyState", "SNSavedElement", "SNSetting"])
    }

    @Test func everyModelRoundTripsThroughAnotherDevice() throws {
        let a = try SyncFixture()
        let keys = try a.populateEverything()
        #expect(Set(keys.map(\.recordType)) == Set(RecordMapper.recordTypes))
        let b = try SyncFixture()
        for key in keys {
            let record = try #require(try RecordMapper.encode(key, in: a.context))
            let outcome = try RecordMapper.applyServer(record, in: b.context, ink: JSONInkMerging())
            #expect(outcome == .created, "\(key.recordType)")
        }
        for key in keys {
            let original = try #require(try RecordMapper.encode(key, in: a.context))
            let copy = try #require(try RecordMapper.encode(key, in: b.context))
            #expect(original.fields == copy.fields, "\(key.recordType) fields differ")
        }
    }

    @Test func serverAppliedRowsAreCleanAndLocalOnlyFieldsStayLocal() throws {
        let a = try SyncFixture()
        let page = try a.syncedPage(strokes: [("a", 1)])
        let record = try #require(try RecordMapper.encode(RecordKey(recordType: "SNPage", id: page.id), in: a.context))
        #expect(record.fields["baseInkData"] == nil && record.fields["baseStrokeIDs"] == nil)
        #expect(record.fields["syncDirty"] == nil && record.fields["dirtyFields"] == nil && record.fields["ckSystemFields"] == nil)
        let b = try SyncFixture()
        _ = try RecordMapper.applyServer(record, in: b.context, ink: JSONInkMerging())
        let copy = try #require(try b.context.fetch(FetchDescriptor<Page>()).first)
        #expect(copy.syncDirty == false && copy.dirtyFields.isEmpty)
        #expect(copy.baseStrokeIDs == ["a"] && copy.baseInkData == copy.inkData)
    }

    @Test func commonFieldsAreWritten() throws {
        let f = try SyncFixture()
        let nb = try f.store.notebook()
        let r = try #require(try RecordMapper.encode(RecordKey(recordType: "SNNotebook", id: nb.id), in: f.context))
        #expect(r.int("formatVersion") == SchemaFormat.currentVersion)
        #expect(r.date("createdAt") != nil && r.date("modifiedAt") != nil && r.deletedAt == nil)
        #expect(r.string("title") == nb.title && r.string("kind") == "paged")
    }

    @Test func softDeleteIsWrittenAsDeletedAt() throws {
        let f = try SyncFixture()
        let nb = try f.store.notebook()
        try f.store.library.softDelete([.notebook(nb.id)])
        let r = try #require(try RecordMapper.encode(RecordKey(recordType: "SNNotebook", id: nb.id), in: f.context))
        #expect(r.deletedAt != nil)
    }

    @Test func unknownFieldsAreIgnoredOnRead() throws {
        let f = try SyncFixture()
        let id = UUID()
        let record = SyncRecord(key: RecordKey(recordType: "SNFolder", id: id), fields: [
            "name": .string("Future"), "sortKey": .string("m"), "formatVersion": .int(1),
            "createdAt": .date(.now), "modifiedAt": .date(.now),
            "shinyNewField": .string("from v2"), "anotherOne": .bytes(Data([1])),
        ])
        #expect(try RecordMapper.applyServer(record, in: f.context, ink: JSONInkMerging()) == .created)
        let row = try #require(try f.context.fetch(FetchDescriptor<Folder>()).first)
        #expect(row.name == "Future")
    }

    @Test func recordFromNewerFormatIsKeptAndNeverUploaded() throws {
        let f = try SyncFixture()
        let id = UUID()
        let record = SyncRecord(key: RecordKey(recordType: "SNFolder", id: id), fields: [
            "name": .string("From the future"), "sortKey": .string("m"), "formatVersion": .int(99),
            "createdAt": .date(.now), "modifiedAt": .date(.now),
        ])
        #expect(try RecordMapper.applyServer(record, in: f.context, ink: JSONInkMerging()) == .created)
        let row = try #require(try f.context.fetch(FetchDescriptor<Folder>()).first)
        #expect(row.formatVersion == 99 && RecordMapper.isReadOnlyFromNewerVersion(row))
        markDirty(row, fields: ["name"])
        #expect(try RecordMapper.dirtyKeys(in: f.context).isEmpty)
        #expect(try RecordMapper.allKeys(in: f.context).isEmpty)
    }

    @Test func unknownRecordTypeIsIgnoredNotCrashed() throws {
        let f = try SyncFixture()
        let record = SyncRecord(key: RecordKey(recordType: "SNHologram", id: UUID()))
        #expect(try RecordMapper.applyServer(record, in: f.context, ink: JSONInkMerging()) == .ignored(.unknownRecordType))
    }

    @Test func recordMissingItsParentIDIsRejectedAsMalformed() throws {
        let f = try SyncFixture()
        let record = SyncRecord(key: RecordKey(recordType: "SNPage", id: UUID()), fields: ["sortKey": .string("m")])
        #expect(try RecordMapper.applyServer(record, in: f.context, ink: JSONInkMerging()) == .ignored(.malformed(field: "notebookID")))
        #expect(try f.context.fetch(FetchDescriptor<Page>()).isEmpty)
    }

    @Test func childArrivingBeforeItsParentIsKept() throws {
        let f = try SyncFixture()
        let record = SyncRecord(key: RecordKey(recordType: "SNPage", id: UUID()), fields: [
            "notebookID": .string(UUID().uuidString), "sortKey": .string("m"),
            "widthPts": .double(100), "heightPts": .double(200),
        ])
        #expect(try RecordMapper.applyServer(record, in: f.context, ink: JSONInkMerging()) == .created)
        #expect(try f.context.fetch(FetchDescriptor<Page>()).count == 1)
    }

    @Test func markAllDirtyFlagsEveryRowAndDropsSystemFields() throws {
        let f = try SyncFixture()
        let keys = try f.populateEverything()
        try f.context.fetch(FetchDescriptor<Folder>()).forEach { $0.ckSystemFields = Data([1]); $0.syncDirty = false }
        let count = try RecordMapper.markAllDirty(in: f.context)
        #expect(count >= keys.count)
        #expect(try RecordMapper.dirtyKeys(in: f.context).count == keys.count)
        #expect(try f.context.fetch(FetchDescriptor<Folder>()).allSatisfy { $0.ckSystemFields == nil })
    }

    @Test func confirmSentClearsDirtyOnlyIfNotEditedSince() throws {
        let f = try SyncFixture()
        let nb = try f.store.notebook()
        let key = RecordKey(recordType: "SNNotebook", id: nb.id)
        let sent = try #require(try RecordMapper.encode(key, in: f.context))
        nb.title = "Edited while sending"
        markDirty(nb, fields: ["title"], now: sent.modifiedAt.addingTimeInterval(5))
        var saved = sent
        saved.systemFields = Data([42])
        try RecordMapper.confirmSent(sent: sent, saved: saved, in: f.context)
        #expect(nb.syncDirty && nb.ckSystemFields == Data([42]))
        let resent = try #require(try RecordMapper.encode(key, in: f.context))
        try RecordMapper.confirmSent(sent: resent, saved: saved, in: f.context)
        #expect(!nb.syncDirty && nb.dirtyFields.isEmpty)
    }
}
