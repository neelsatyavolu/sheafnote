import Foundation
import Testing
import SheafnoteCore
@testable import Sheafnote

@MainActor
@Suite struct SearchServiceTests {
    @Test func findsTitlesHandwritingTypedTextAndPdfText() async throws {
        let f = try SearchFixture()
        let physics = try f.notebook("Physics notes", pages: 2)
        let pages = try f.pages(of: physics)
        pages[0].recognizedText = "conservation of momentum"
        let payload = PayloadCodec.encode(TextPayload(text: "remember the flux capacitor"))
        try f.services.pages.insertElement(ElementValue(pageID: pages[1].id, kind: .text,
                                                        frame: CGRect(x: 0, y: 0, width: 100, height: 30), payload: payload))
        let book = try f.notebook("Textbook", pages: 2)
        let bookPages = try f.pages(of: book)
        let asset = try f.services.pages.importAsset(data: SearchFixture.pdf(pages: ["Opening", "Entropy and heat"]),
                                                     kind: .pdf, filename: "book.pdf")
        for (i, page) in bookPages.enumerated() {
            page.backgroundAssetID = asset.id
            page.backgroundPageIndex = i
        }
        try f.services.context.save()

        await f.service.refreshIndex()

        #expect(f.service.search("physics").first?.documentID == SearchDocumentID(kind: .notebookTitle, id: physics.id))
        #expect(f.service.search("momentum").first?.documentID == SearchDocumentID(kind: .page, id: pages[0].id))
        #expect(f.service.search("capacitor").first?.documentID == SearchDocumentID(kind: .page, id: pages[1].id))
        let pdfHit = try #require(f.service.search("entropy").first)
        #expect(pdfHit.documentID == SearchDocumentID(kind: .page, id: bookPages[1].id))
        #expect(pdfHit.field == .pdf)
        #expect(f.service.search("entropy", notebookID: physics.id).isEmpty)
    }

    @Test func refreshPicksUpNewTextAndDropsDeletedNotebooks() async throws {
        let f = try SearchFixture()
        let nb = try f.notebook("Journal")
        let page = try #require(try f.pages(of: nb).first)
        await f.service.refreshIndex()
        #expect(f.service.search("elephant").isEmpty)

        page.recognizedText = "an elephant at the zoo"
        page.modifiedAt = .now
        try f.services.context.save()
        let before = f.service.revision
        await f.service.refreshIndex()
        #expect(f.service.search("elephant").count == 1)
        #expect(f.service.revision > before)

        try f.services.library.softDelete([.notebook(nb.id)])
        await f.service.refreshIndex()
        #expect(f.service.search("elephant").isEmpty)
        #expect(f.service.search("journal").isEmpty)
    }

    @Test func rebuildQueuesEveryPageAgainButKeepsOldText() async throws {
        let f = try SearchFixture()
        let nb = try f.notebook("Old")
        let page = try #require(try f.pages(of: nb).first)
        try f.writeInk(on: page)
        f.service.ocr.start(force: true)
        await f.service.ocr.waitUntilIdle()
        #expect(f.recognizer.calls == 1)

        f.recognizer.text = "new reading"
        try f.service.rebuild()
        await f.service.ocr.waitUntilIdle()
        #expect(f.recognizer.calls == 2)
        #expect(page.recognizedText == "new reading")
    }

    @Test func unreadableAttachmentJustHasNoText() async throws {
        let f = try SearchFixture()
        let nb = try f.notebook("Photos")
        let page = try #require(try f.pages(of: nb).first)
        let asset = try f.services.pages.importAsset(data: Data("not a pdf".utf8), kind: .image, filename: "a.png")
        page.backgroundAssetID = asset.id
        page.backgroundPageIndex = 0
        try f.services.context.save()
        await f.service.refreshIndex()
        #expect(f.service.search("photos").count == 1)
        await f.service.refreshIndex()    // does not retry or crash
    }
}
