import Foundation
import SwiftData
import Testing
@testable import SheafnoteCore

@MainActor
@Suite("Asset references")
struct AssetReferenceTests {
    private func richText(imageAsset: UUID) -> Data {
        RichTextDocument(blocks: [RichTextBlock(kind: .paragraph, text: "hi"),
                                  RichTextBlock(kind: .image, assetID: imageAsset)]).encoded()
    }

    private func savedElement(image: UUID, pageID: UUID, in f: StoreFixture) -> SavedElement {
        let value = ElementValue(pageID: pageID, kind: .image, frame: .zero, assetID: image)
        let row = SavedElement(name: "Pic", category: "Mine", width: 1, height: 1, inkData: nil,
                               elements: JSONCoding.encode([value]), thumbnail: Data([1]))
        f.context.insert(row)
        return row
    }

    @Test func scansAssetIDsInsideJSON() {
        let id = UUID()
        let json = Data(#"{"a":[{"assetID":"\#(id.uuidString)"},{"x":1}],"assetID":null}"#.utf8)
        #expect(AssetReferences.ids(inJSON: json) == [id])
        #expect(AssetReferences.ids(inJSON: nil).isEmpty)
        #expect(AssetReferences.ids(inJSON: Data("not json".utf8)).isEmpty)
    }

    @Test func savedElementImageSurvivesPurgeOfSourceNotebook() throws {
        let f = try StoreFixture()
        let nb = try f.notebook("Source")
        let page = try #require(try f.pages.orderedPages(of: nb.id).first)
        let image = try f.pages.importAsset(data: Data([7, 7, 7]), kind: .image, filename: nil)
        try f.pages.insertElement(ElementValue(pageID: page.id, kind: .image, frame: .zero, assetID: image.id))
        _ = savedElement(image: image.id, pageID: page.id, in: f)
        try f.context.save()
        let now = Date(timeIntervalSince1970: 500 * day)
        try f.library.softDelete([.notebook(nb.id)], now: now - 40 * day)
        try f.library.purgeExpired(now: now)
        #expect(try f.context.fetch(FetchDescriptor<Asset>()).contains { $0.id == image.id })
    }

    @Test func textDocumentImageSurvivesDeletePermanentlyOfSharingNotebook() throws {
        let f = try StoreFixture()
        let a = try f.notebook("A"), doc = try f.notebook("Doc", kind: .text)
        let page = try #require(try f.pages.orderedPages(of: a.id).first)
        let image = try f.pages.importAsset(data: Data([5, 5]), kind: .image, filename: nil)
        try f.pages.insertElement(ElementValue(pageID: page.id, kind: .image, frame: .zero, assetID: image.id))
        doc.richText = richText(imageAsset: image.id)
        try f.context.save()
        try f.library.softDelete([.notebook(a.id)])
        try f.library.deletePermanently([.notebook(a.id)])
        #expect(try f.context.fetch(FetchDescriptor<Asset>()).contains { $0.id == image.id })
    }

    @Test func revisionImageSurvivesPurge() throws {
        let f = try StoreFixture()
        let a = try f.notebook("A"), b = try f.notebook("B")
        let pageA = try #require(try f.pages.orderedPages(of: a.id).first)
        let pageB = try #require(try f.pages.orderedPages(of: b.id).first)
        let image = try f.pages.importAsset(data: Data([4]), kind: .image, filename: nil)
        try f.pages.insertElement(ElementValue(pageID: pageA.id, kind: .image, frame: .zero, assetID: image.id))
        try f.revisions.snapshot(page: pageA, reason: .beforeDelete)
        _ = pageB
        let now = Date(timeIntervalSince1970: 500 * day)
        try f.library.softDelete([.notebook(a.id)], now: now - 40 * day)
        try f.library.purgeExpired(now: now)
        #expect(try f.context.fetch(FetchDescriptor<Asset>()).contains { $0.id == image.id })
    }

    @Test func purgingAPageAlsoErasesItsElementsBookmarksAndOutline() throws {
        let f = try StoreFixture()
        let nb = try f.notebook()
        let extra = try f.pages.addPage(to: nb.id, at: .end, template: nil)
        let image = try f.pages.importAsset(data: Data([3, 3]), kind: .image, filename: nil)
        try f.pages.insertElement(ElementValue(pageID: extra.id, kind: .image, frame: .zero, assetID: image.id))
        f.context.insert(Bookmark(notebookID: nb.id, pageID: extra.id))
        f.context.insert(OutlineEntry(notebookID: nb.id, title: "T", pageID: extra.id, sortKey: "V"))
        try f.context.save()
        var purged: [PurgedRecord] = []
        f.library.onPurge = { purged = $0 }
        let now = Date(timeIntervalSince1970: 300 * day)
        try f.pages.softDelete(pageIDs: [extra.id], now: now - 31 * day)
        try f.library.purgeExpired(now: now)
        #expect(try f.context.fetch(FetchDescriptor<PageElement>()).isEmpty)
        #expect(try f.context.fetch(FetchDescriptor<Bookmark>()).isEmpty)
        #expect(try f.context.fetch(FetchDescriptor<OutlineEntry>()).isEmpty)
        for type in ["SNPageElement", "SNBookmark", "SNOutlineEntry"] {
            #expect(purged.contains { $0.recordType == type }, "missing queued delete for \(type)")
        }
    }
}
