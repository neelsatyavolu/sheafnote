import SwiftData
import XCTest
@testable import SheafnoteCore

@MainActor
final class SearchCorpusTests: XCTestCase {
    private func firstPage(_ f: StoreFixture, of nb: Notebook) throws -> Page {
        try XCTUnwrap(f.pages.orderedPages(of: nb.id).first)
    }

    private func addText(_ f: StoreFixture, page: Page, _ text: String) throws {
        let payload = PayloadCodec.encode(TextPayload(text: text))
        try f.pages.insertElement(ElementValue(pageID: page.id, kind: .text, frame: CGRect(x: 0, y: 0, width: 50, height: 20), payload: payload))
    }

    func testIndexesTitlesHandwritingTypedTextAndPdfText() throws {
        let f = try StoreFixture()
        let folder = try f.library.createFolder(name: "Chemistry", in: nil)
        let nb = try f.notebook("Physics lecture")
        let page = try firstPage(f, of: nb)
        page.recognizedText = "momentum conservation"
        page.backgroundAssetID = UUID()
        page.backgroundPageIndex = 1
        let assetID = try XCTUnwrap(page.backgroundAssetID)
        try addText(f, page: page, "remember the lab report")
        try f.context.save()

        let corpus = SearchCorpus(context: f.context)
        var index = SearchIndex()
        try corpus.refresh(&index, pdfTexts: [assetID: ["", "entropy always grows"]])

        XCTAssertEqual(index.search("chemistry").map(\.documentID), [SearchDocumentID(kind: .folderTitle, id: folder.id)])
        XCTAssertEqual(index.search("physics").first?.documentID, SearchDocumentID(kind: .notebookTitle, id: nb.id))
        let byHandwriting = index.search("momentum").first
        XCTAssertEqual(byHandwriting?.documentID, SearchDocumentID(kind: .page, id: page.id))
        XCTAssertEqual(byHandwriting?.field, .handwriting)
        XCTAssertEqual(index.search("report").first?.field, .typed)
        XCTAssertEqual(index.search("entropy").first?.field, .pdf)
    }

    func testSecondRefreshSkipsUnchangedAndPicksUpEdits() throws {
        let f = try StoreFixture()
        let nb = try f.notebook("Notes")
        let page = try firstPage(f, of: nb)
        let corpus = SearchCorpus(context: f.context)
        var index = SearchIndex()
        let first = try corpus.refresh(&index)
        XCTAssertGreaterThan(first.updated, 0)
        XCTAssertEqual(try corpus.refresh(&index), CorpusRefresh())

        _ = try f.pages.saveInk(pageID: page.id, drawingData: Data([1]), strokeIDs: [StrokeID(rawValue: "a")])
        let stored = try PageTextStore(context: f.context).store(text: "fresh words", forInkHash: page.inkHash, pageID: page.id)
        XCTAssertTrue(stored)
        XCTAssertEqual(try corpus.refresh(&index).updated, 1)
        XCTAssertEqual(index.search("fresh").count, 1)
    }

    func testDeletedAndLockedContentLeavesTheIndex() throws {
        let f = try StoreFixture()
        let nb = try f.notebook("Secret plans")
        let page = try firstPage(f, of: nb)
        page.recognizedText = "launch codes"
        try f.context.save()
        let corpus = SearchCorpus(context: f.context)
        var index = SearchIndex()
        try corpus.refresh(&index)
        XCTAssertEqual(index.search("launch").count, 1)

        nb.isLocked = true
        try f.context.save()
        try corpus.refresh(&index)
        XCTAssertTrue(index.search("launch").isEmpty)
        XCTAssertEqual(index.search("secret").count, 1)      // the title stays findable

        nb.isLocked = false
        try f.library.softDelete([.notebook(nb.id)])
        let report = try corpus.refresh(&index)
        XCTAssertGreaterThan(report.removed, 0)
        XCTAssertTrue(index.search("secret").isEmpty)
        XCTAssertTrue(index.search("launch").isEmpty)
    }

    func testTextDocumentsAreIndexedFromRichText() throws {
        let f = try StoreFixture()
        let nb = try f.notebook("Journal", kind: .text)
        nb.richText = Data(#"{"blocks":[{"kind":"heading","text":"Groceries"},{"kind":"list","items":[{"text":"oat milk"}]}]}"#.utf8)
        try f.context.save()
        var index = SearchIndex()
        try SearchCorpus(context: f.context).refresh(&index)
        XCTAssertEqual(index.search("oat").first?.documentID, SearchDocumentID(kind: .textDocument, id: nb.id))
        XCTAssertEqual(index.search("groceries").count, 1)
    }

    func testMissingPDFAssetsListsOnlyUncachedBackgrounds() throws {
        let f = try StoreFixture()
        let nb = try f.notebook("Book")
        let page = try firstPage(f, of: nb)
        let asset = UUID()
        page.backgroundAssetID = asset
        page.backgroundPageIndex = 0
        try f.context.save()
        let corpus = SearchCorpus(context: f.context)
        XCTAssertEqual(try corpus.missingPDFAssets(cache: [:]), [asset])
        XCTAssertTrue(try corpus.missingPDFAssets(cache: [asset: ["x"]]).isEmpty)
    }

    func testRichTextExtractorHandlesGarbage() {
        XCTAssertEqual(RichTextExtractor.plainText(fromJSON: Data("nope".utf8)), "")
        XCTAssertEqual(RichTextExtractor.plainText(fromJSON: Data(#"[{"text":"a"},{"x":{"text":"b"}}]"#.utf8)), "a\nb")
    }
}
