import CoreGraphics
import Foundation
import SwiftData
import Testing
@testable import SheafnoteCore

@MainActor
@Suite("PDF and image import")
struct PdfImporterTests {
    private func importer(_ fx: StoreFixture) -> PdfImporter { PdfImporter(context: fx.context, pages: fx.pages) }

    @Test func pdfBecomesANotebookWithOneBackedPagePerPdfPage() async throws {
        let fx = try StoreFixture()
        let sizes = [CGSize(width: 612, height: 792), CGSize(width: 792, height: 612), CGSize(width: 300, height: 400)]
        let result = try await importer(fx).importPDF(PDFFixtures.pdf(sizes: sizes), title: "Lecture Slides", into: nil)

        let notebook = try #require(fx.library.notebook(id: result.notebookID))
        #expect(notebook.title == "Lecture Slides" && notebook.kind == .paged)
        let pages = try fx.pages.orderedPages(of: notebook.id)
        #expect(pages.map(\.id) == result.pageIDs)
        #expect(pages.map(\.size) == sizes)
        #expect(pages.map(\.backgroundPageIndex) == [0, 1, 2])
        #expect(Set(pages.compactMap(\.backgroundAssetID)).count == 1, "one stored PDF for all pages")
        #expect(pages.allSatisfy { $0.template?.kind == .blank })
        let assets = try fx.context.fetch(FetchDescriptor<Asset>())
        #expect(assets.count == 1 && assets[0].kind == .pdf)
        #expect(notebook.pdfOutlineImported)
    }

    @Test func notebookPaperFollowsTheFirstPage() async throws {
        let fx = try StoreFixture()
        let letterLandscape = try await importer(fx).importPDF(PDFFixtures.pdf(sizes: [CGSize(width: 792, height: 612)]), title: "L", into: nil)
        let nb = try #require(fx.library.notebook(id: letterLandscape.notebookID))
        #expect(nb.paperSizeValue == .letter && nb.orientationValue == .landscape)
    }

    @Test func importedPdfNotebookHasNoStrayBlankPage() async throws {
        let fx = try StoreFixture()
        let result = try await importer(fx).importPDF(PDFFixtures.pdf(pages: 2), title: "Two", into: nil)
        #expect(try fx.pages.orderedPages(of: result.notebookID).count == 2)
    }

    @Test func outlineBecomesPdfSourcedEntriesLinkedToPages() async throws {
        let fx = try StoreFixture()
        let result = try await importer(fx).importPDF(PDFFixtures.pdfWithOutline(), title: "Book", into: nil)
        #expect(result.outlineEntryCount == 3)
        let entries = try fx.context.fetch(FetchDescriptor<OutlineEntry>()).sorted { $0.sortKey < $1.sortKey }
        #expect(entries.map(\.title) == ["Chapter 1", "Section 1.1", "Chapter 2"])
        #expect(entries.allSatisfy { $0.source == OutlineSource.pdf.rawValue && $0.notebookID == result.notebookID })
        #expect(entries.map(\.pageID) == [result.pageIDs[0], result.pageIDs[2], result.pageIDs[1]])
        #expect(entries.map(\.pdfPageIndex) == [0, 2, 1])
        #expect(entries[1].parentID == entries[0].id && entries[0].parentID == nil)
    }

    @Test func insertingIntoAnExistingNotebookPlacesPagesAtThePosition() async throws {
        let fx = try StoreFixture()
        let nb = try fx.notebook("Mine")
        let second = try fx.pages.addPage(to: nb.id, at: .end, template: nil)
        let third = try fx.pages.addPage(to: nb.id, at: .end, template: nil)
        let originalIDs = try fx.pages.orderedPages(of: nb.id).map(\.id)

        let result = try await importer(fx).insertPDF(PDFFixtures.pdf(pages: 3), filename: "x.pdf", into: nb.id, at: .after(originalIDs[0]))
        let order = try fx.pages.orderedPages(of: nb.id).map(\.id)
        #expect(order == [originalIDs[0]] + result.pageIDs + [second.id, third.id])
        let inserted = try fx.pages.orderedPages(of: nb.id).dropFirst().prefix(3)
        #expect(inserted.map(\.backgroundPageIndex) == [0, 1, 2])
        #expect(inserted.allSatisfy { $0.size == CGSize(width: 612, height: 792) })
        // The existing pages are untouched.
        let first = try #require(fx.pages.page(id: originalIDs[0]))
        #expect(first.backgroundAssetID == nil)
    }

    @Test func insertAtTheEndAndBeforeAPage() async throws {
        let fx = try StoreFixture()
        let nb = try fx.notebook()
        let only = try fx.pages.orderedPages(of: nb.id)[0].id
        let tail = try await importer(fx).insertPDF(PDFFixtures.pdf(pages: 2), filename: nil, into: nb.id, at: .end)
        let head = try await importer(fx).insertPDF(PDFFixtures.pdf(pages: 2), filename: nil, into: nb.id, at: .before(only))
        let order = try fx.pages.orderedPages(of: nb.id).map(\.id)
        #expect(order == head.pageIDs + [only] + tail.pageIDs)
    }

    @Test func insertingThesamePdfTwiceStoresTheFileOnce() async throws {
        let fx = try StoreFixture()
        let nb = try fx.notebook()
        let data = PDFFixtures.pdf(pages: 1)
        _ = try await importer(fx).insertPDF(data, filename: "a.pdf", into: nb.id, at: .end)
        _ = try await importer(fx).insertPDF(data, filename: "a.pdf", into: nb.id, at: .end)
        #expect(try fx.context.fetch(FetchDescriptor<Asset>()).count == 1)
    }

    @Test func badPdfLeavesTheLibraryUntouched() async throws {
        let fx = try StoreFixture()
        await #expect(throws: PdfIOError.unreadablePDF) {
            try await importer(fx).importPDF(Data("junk".utf8), title: "Bad", into: nil)
        }
        #expect(try fx.library.allNotebooks().isEmpty)
        #expect(try fx.context.fetch(FetchDescriptor<Asset>()).isEmpty)
    }

    @Test func importsLandOnlyInPagedNotebooks() async throws {
        let fx = try StoreFixture()
        let doc = try fx.notebook("Essay", kind: .text)
        await #expect(throws: PdfIOError.notAPagedNotebook) {
            try await importer(fx).insertPDF(PDFFixtures.pdf(pages: 1), filename: nil, into: doc.id, at: .end)
        }
        await #expect(throws: PdfIOError.notebookMissing) {
            try await importer(fx).insertPDF(PDFFixtures.pdf(pages: 1), filename: nil, into: UUID(), at: .end)
        }
    }

    @Test func importsIntoTheRequestedFolderAfterExistingNotebooks() async throws {
        let fx = try StoreFixture()
        let folder = try fx.library.createFolder(name: "F", in: nil)
        let existing = try fx.notebook("Old", in: folder.id)
        let result = try await importer(fx).importPDF(PDFFixtures.pdf(pages: 1), title: "New", into: folder.id)
        let created = try #require(fx.library.notebook(id: result.notebookID))
        #expect(created.folderID == folder.id && created.sortKey > existing.sortKey)
    }

    @Test func imagesBecomePagesSizedToTheirAspect() async throws {
        let fx = try StoreFixture()
        let images = [ImportedImage(data: PDFFixtures.png(width: 400, height: 300), filename: "wide.png"),
                      ImportedImage(data: PDFFixtures.png(width: 100, height: 200), filename: "tall.png")]
        let result = try await importer(fx).importImages(images, title: "Scans", into: nil)
        let pages = try fx.pages.orderedPages(of: result.notebookID)
        #expect(pages.count == 2)
        #expect(pages[0].size == CGSize(width: 842, height: 632) && pages[1].size == CGSize(width: 421, height: 842))
        #expect(pages.allSatisfy { $0.backgroundAssetID != nil && $0.backgroundPageIndex == nil })
        let assets = try fx.context.fetch(FetchDescriptor<Asset>())
        #expect(assets.count == 2 && assets.allSatisfy { $0.kind == .image })
    }

    @Test func imagesInsertIntoAnExistingNotebook() async throws {
        let fx = try StoreFixture()
        let nb = try fx.notebook()
        let result = try await importer(fx).insertImages([ImportedImage(data: PDFFixtures.png(width: 10, height: 10), filename: "a.png")],
                                                         into: nb.id, at: .end)
        #expect(try fx.pages.orderedPages(of: nb.id).count == 2 && result.pageIDs.count == 1)
    }

    @Test func unreadableImagesAndEmptyListsAreRejected() async throws {
        let fx = try StoreFixture()
        await #expect(throws: PdfIOError.unreadableImage("bad.png")) {
            try await importer(fx).importImages([ImportedImage(data: Data("x".utf8), filename: "bad.png")], title: "T", into: nil)
        }
        await #expect(throws: PdfIOError.nothingToImport) { try await importer(fx).importImages([], title: "T", into: nil) }
        #expect(try fx.library.allNotebooks().isEmpty)
    }

    @Test func fiveHundredPagePdfImportsWithinTheTimeBudget() async throws {
        let fx = try StoreFixture()
        let data = PDFFixtures.pdf(pages: 500)
        let start = Date()
        let result = try await importer(fx).importPDF(data, title: "Big", into: nil)
        let elapsed = Date().timeIntervalSince(start)
        #expect(result.pageIDs.count == 500)
        #expect(try fx.pages.orderedPages(of: result.notebookID).count == 500)
        #expect(elapsed < 5, "500-page import took \(elapsed) s")
    }

    @Test func closestPaperPicksTheNearestAspect() {
        #expect(PdfImporter.closestPaper(to: CGSize(width: 595, height: 842)).paper == .a4)
        #expect(PdfImporter.closestPaper(to: CGSize(width: 612, height: 792)).paper == .letter)
        #expect(PdfImporter.closestPaper(to: CGSize(width: 500, height: 500)).paper == .square)
        #expect(PdfImporter.closestPaper(to: CGSize(width: 500, height: 500)).orientation == .portrait)
        #expect(PdfImporter.closestPaper(to: CGSize(width: 842, height: 595)).orientation == .landscape)
    }
}
