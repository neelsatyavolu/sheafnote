import Foundation
import SwiftData
import Testing
@testable import SheafnoteCore

/// Applying server versions onto rows that have local unsent changes.
@MainActor
@Suite struct RecordMergeTests {
    private let ink = JSONInkMerging()

    private func serverVersion(of page: Page, in f: SyncFixture, strokes: [(String, Double)]? = nil,
                               mutate: (inout SyncRecord) -> Void = { _ in }) throws -> SyncRecord {
        var rec = try #require(try RecordMapper.encode(RecordKey(recordType: "SNPage", id: page.id), in: f.context))
        if let strokes {
            rec.fields["inkData"] = .bytes(JSONInkMerging.data(strokes))
            rec.fields["strokeIDs"] = .strings(JSONInkMerging.ids(strokes))
            rec.fields["inkHash"] = .string(Hashing.sha256Hex(JSONInkMerging.data(strokes)))
        }
        rec.fields["modifiedAt"] = .date(.now.addingTimeInterval(100))
        rec.systemFields = Data([7])
        mutate(&rec)
        return rec
    }

    private func strokeIDs(_ page: Page) -> [String] { page.strokeIDs }

    @Test func concurrentInkAdditionsMergeAndStayDirtyForResend() throws {
        let f = try SyncFixture()
        let page = try f.syncedPage(strokes: [("a", 1)])
        try f.edit(page, strokes: [("a", 1), ("b", 2)])
        let theirs = try serverVersion(of: page, in: f, strokes: [("a", 1), ("c", 3)])
        #expect(try RecordMapper.applyServer(theirs, in: f.context, ink: ink) == .merged)
        #expect(strokeIDs(page) == ["a", "b", "c"])
        #expect(page.syncDirty && page.dirtyFields.contains("inkData"))
        #expect(page.baseStrokeIDs == ["a", "c"])
        #expect(page.ckSystemFields == Data([7]))
        let decoded = try JSONDecoder().decode([JSONInkMerging.Item].self, from: try #require(page.inkData))
        #expect(decoded.map(\.id) == ["a", "b", "c"])
        #expect(page.inkHash == Hashing.sha256Hex(try #require(page.inkData)))
    }

    @Test func concurrentInkDeletionsBothApply() throws {
        let f = try SyncFixture()
        let page = try f.syncedPage(strokes: [("a", 1), ("b", 2), ("c", 3)])
        try f.edit(page, strokes: [("b", 2), ("c", 3)])
        let theirs = try serverVersion(of: page, in: f, strokes: [("a", 1), ("c", 3)])
        _ = try RecordMapper.applyServer(theirs, in: f.context, ink: ink)
        #expect(strokeIDs(page) == ["c"])
    }

    @Test func deleteVersusEditKeepsTheEdit() throws {
        let f = try SyncFixture()
        let page = try f.syncedPage(strokes: [("a", 1)])
        try f.edit(page, strokes: [("a2", 5)])                        // we edited a
        let theirs = try serverVersion(of: page, in: f, strokes: [])    // they deleted a
        _ = try RecordMapper.applyServer(theirs, in: f.context, ink: ink)
        #expect(strokeIDs(page) == ["a2"])
    }

    @Test func identicalInkOnBothSidesIsNotAConflict() throws {
        let f = try SyncFixture()
        let page = try f.syncedPage(strokes: [("a", 1)])
        try f.edit(page, strokes: [("a", 1), ("b", 2)])
        let theirs = try serverVersion(of: page, in: f, strokes: [("a", 1), ("b", 2)])
        let revisionsBefore = try f.context.fetch(FetchDescriptor<PageRevision>()).count
        _ = try RecordMapper.applyServer(theirs, in: f.context, ink: ink)
        #expect(!page.syncDirty)
        #expect(try f.context.fetch(FetchDescriptor<PageRevision>()).count == revisionsBefore)
    }

    @Test func mergeAlwaysSnapshotsOursIntoRecovered() throws {
        let f = try SyncFixture()
        let page = try f.syncedPage(strokes: [("a", 1)])
        try f.edit(page, strokes: [("a", 1), ("b", 2)])
        _ = try RecordMapper.applyServer(try serverVersion(of: page, in: f, strokes: [("a", 1), ("c", 3)]), in: f.context, ink: ink)
        let revisions = try f.context.fetch(FetchDescriptor<PageRevision>())
        let snapshot = try #require(revisions.first { $0.reasonValue == .conflict && $0.strokeIDs == ["a", "b"] })
        #expect(snapshot.expiresAt > snapshot.createdAt)
    }

    @Test func pageNeverSyncedFromHereUnionsInsteadOfOverwriting() throws {
        let f = try SyncFixture()
        let nb = try f.store.notebook()
        let page = try f.store.pages.addPage(to: nb.id, at: .end, template: nil)
        try f.edit(page, strokes: [("mine", 1)])                        // no base: baseStrokeIDs empty
        #expect(page.baseStrokeIDs.isEmpty)
        let theirs = try serverVersion(of: page, in: f, strokes: [("theirs", 2)])
        _ = try RecordMapper.applyServer(theirs, in: f.context, ink: ink)
        #expect(strokeIDs(page) == ["mine", "theirs"])
    }

    @Test func corruptServerInkKeepsOursAndRecoversTheirs() throws {
        let f = try SyncFixture()
        let page = try f.syncedPage(strokes: [("a", 1)])
        try f.edit(page, strokes: [("a", 1), ("b", 2)])
        let corrupt = Data("not a drawing".utf8)
        let theirs = try serverVersion(of: page, in: f) { rec in
            rec.fields["inkData"] = .bytes(corrupt)
            rec.fields["strokeIDs"] = .strings(["z"])
            rec.fields["inkHash"] = .string("different")
        }
        #expect(try RecordMapper.applyServer(theirs, in: f.context, ink: ink) == .keptBothVersions)
        #expect(strokeIDs(page) == ["a", "b"])
        #expect(page.syncDirty && page.dirtyFields.contains("inkData"))
        let recovered = try f.context.fetch(FetchDescriptor<PageRevision>()).filter { $0.inkData == corrupt }
        #expect(recovered.count == 1 && recovered[0].reasonValue == .conflict && recovered[0].pageID == page.id)
    }

    @Test func unavailableInkEngineFallsBackToKeepBoth() throws {
        let f = try SyncFixture()
        let page = try f.syncedPage(strokes: [("a", 1)])
        try f.edit(page, strokes: [("a", 1), ("b", 2)])
        let theirs = try serverVersion(of: page, in: f, strokes: [("a", 1), ("c", 3)])
        #expect(try RecordMapper.applyServer(theirs, in: f.context, ink: UnavailableInkMerging()) == .keptBothVersions)
        #expect(strokeIDs(page) == ["a", "b"])
        #expect(try f.context.fetch(FetchDescriptor<PageRevision>()).contains { $0.strokeIDs == ["a", "c"] })
    }

    @Test func nonInkFieldsMergePerField() throws {
        let f = try SyncFixture()
        let page = try f.syncedPage(strokes: [("a", 1)])
        page.sortKey = "ours"
        markDirty(page, fields: ["sortKey"])
        let theirs = try serverVersion(of: page, in: f) { rec in
            rec.fields["sortKey"] = .string("theirs")
            rec.fields["recognizedText"] = .string("server ocr")
        }
        _ = try RecordMapper.applyServer(theirs, in: f.context, ink: ink)
        #expect(page.sortKey == "ours")
        #expect(page.recognizedText == "server ocr")
        #expect(page.dirtyFields == ["sortKey"])
    }

    @Test func cleanRowTakesTheServerVersionWholesale() throws {
        let f = try SyncFixture()
        let page = try f.syncedPage(strokes: [("a", 1)])
        let theirs = try serverVersion(of: page, in: f, strokes: [("a", 1), ("x", 2)])
        #expect(try RecordMapper.applyServer(theirs, in: f.context, ink: ink) == .updated)
        #expect(strokeIDs(page) == ["a", "x"] && page.baseStrokeIDs == ["a", "x"] && !page.syncDirty)
    }

    @Test func serverTombstoneBeatsLocalEditButKeepsTheEditInTrash() throws {
        let f = try SyncFixture()
        let nb = try f.store.notebook("Old")
        nb.title = "Edited here"
        markDirty(nb, fields: ["title"])
        var rec = try #require(try RecordMapper.encode(RecordKey(recordType: "SNNotebook", id: nb.id), in: f.context))
        rec.fields["title"] = .string("Old")
        rec.fields["deletedAt"] = .date(.now)
        #expect(try RecordMapper.applyServer(rec, in: f.context, ink: ink) == .merged)
        #expect(nb.deletedAt != nil)
        #expect(nb.title == "Edited here")
    }

    @Test func serverDeletionOfATrashedRowRemovesIt() throws {
        let f = try SyncFixture()
        let nb = try f.store.notebook()
        try f.store.library.softDelete([.notebook(nb.id)])
        let outcome = try RecordMapper.applyServerDeletion(RecordKey(recordType: "SNNotebook", id: nb.id), in: f.context)
        #expect(outcome == .deleted)
        #expect(try f.context.fetch(FetchDescriptor<Notebook>()).isEmpty)
    }

    @Test func serverDeletionOfALiveRowNeverDeletesLocalDataAndReuploads() throws {
        let f = try SyncFixture()
        let nb = try f.store.notebook()
        nb.syncDirty = false
        nb.ckSystemFields = Data([1])
        let outcome = try RecordMapper.applyServerDeletion(RecordKey(recordType: "SNNotebook", id: nb.id), in: f.context)
        #expect(outcome == .resurrected)
        #expect(try f.context.fetch(FetchDescriptor<Notebook>()).count == 1)
        #expect(nb.syncDirty && nb.ckSystemFields == nil)
    }
}

@MainActor
@Suite struct TextDocumentConflictTests {
    private func text(_ s: String) -> Data { RichTextDocument(blocks: [RichTextBlock(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, text: s)]).encoded() }

    @Test func concurrentTextEditsKeepTheLosingVersionAsACopy() throws {
        let f = try SyncFixture()
        let doc = try f.store.notebook("Essay", kind: .text)
        doc.richText = text("base")
        doc.dirtyFields = []; doc.syncDirty = false
        try f.context.save()
        doc.richText = text("ours")
        markDirty(doc, fields: ["richText"])
        var rec = try #require(try RecordMapper.encode(RecordKey(recordType: "SNNotebook", id: doc.id), in: f.context))
        rec.fields["richText"] = .bytes(text("theirs"))
        rec.fields["modifiedAt"] = .date(.now.addingTimeInterval(100))
        rec.systemFields = Data([7])

        _ = try RecordMapper.applyServer(rec, in: f.context, ink: JSONInkMerging())

        #expect(doc.richText == text("ours"))
        let copies = try f.context.fetch(FetchDescriptor<Notebook>()).filter { $0.title == "Essay" + TextConflictCopy.titleSuffix }
        #expect(copies.count == 1)
        #expect(copies.first?.richText == text("theirs") && copies.first?.syncDirty == true)
    }

    @Test func identicalTextOnBothSidesMakesNoCopy() throws {
        let f = try SyncFixture()
        let doc = try f.store.notebook("Essay", kind: .text)
        doc.richText = text("same")
        markDirty(doc, fields: ["richText"])
        var rec = try #require(try RecordMapper.encode(RecordKey(recordType: "SNNotebook", id: doc.id), in: f.context))
        rec.systemFields = Data([7])
        _ = try RecordMapper.applyServer(rec, in: f.context, ink: JSONInkMerging())
        #expect(try f.context.fetch(FetchDescriptor<Notebook>()).count == 1)
    }
}
