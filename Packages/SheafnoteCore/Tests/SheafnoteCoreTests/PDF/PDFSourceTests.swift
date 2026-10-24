import CoreGraphics
import Foundation
import Testing
@testable import SheafnoteCore

@Suite("PDF source")
struct PDFSourceTests {
    @Test func readsPageCountAndSizes() throws {
        let sizes = [CGSize(width: 612, height: 792), CGSize(width: 300, height: 200)]
        let source = try PDFSource(data: PDFFixtures.pdf(sizes: sizes))
        #expect(source.pageCount == 2)
        #expect(source.sizes() == sizes)
    }

    @Test func quarterTurnPagesSwapWidthAndHeight() throws {
        let source = try PDFSource(data: PDFFixtures.pdfWithRotation(size: CGSize(width: 200, height: 100), degrees: 90))
        #expect(source.size(ofPage: 0) == CGSize(width: 100, height: 200))
    }

    @Test func rejectsGarbageAndEmptyDocuments() {
        #expect(throws: PdfIOError.unreadablePDF) { try PDFSource(data: Data("not a pdf".utf8)) }
        #expect(throws: PdfIOError.unreadablePDF) { try PDFSource(data: Data()) }
    }

    @Test func outlineIsFlattenedWithDepthAndParents() throws {
        let source = try PDFSource(data: PDFFixtures.pdfWithOutline())
        let outline = source.outline()
        #expect(outline.map(\.title) == ["Chapter 1", "Section 1.1", "Chapter 2"])
        #expect(outline.map(\.pageIndex) == [0, 2, 1])
        #expect(outline.map(\.depth) == [0, 1, 0])
        #expect(outline.map(\.parent) == [nil, 0, nil])
    }

    @Test func documentWithoutOutlineHasNone() throws {
        #expect(try PDFSource(data: PDFFixtures.pdf(pages: 2)).outline().isEmpty)
    }

    @Test func drawsTopOfThePageAtTheTopOfAYDownContext() throws {
        let size = CGSize(width: 200, height: 300)
        let source = try PDFSource(data: PDFFixtures.pdf(sizes: [size], barHeight: 30))
        let ctx = PDFFixtures.pageContext(size)
        source.draw(pageIndex: 0, in: ctx, rect: CGRect(origin: .zero, size: size))
        #expect(PDFFixtures.luma(ctx, x: 100, y: 10) < 40, "the black bar is at the top")
        #expect(PDFFixtures.luma(ctx, x: 100, y: 150) > 215, "the rest of the page stays white")
        #expect(PDFFixtures.luma(ctx, x: 100, y: 290) > 215)
    }

    @Test func scalesToTheTargetRectAndKeepsOutsideUntouched() throws {
        let source = try PDFSource(data: PDFFixtures.pdf(sizes: [CGSize(width: 100, height: 100)], barHeight: 50))
        let ctx = PDFFixtures.pageContext(CGSize(width: 200, height: 200))
        source.draw(pageIndex: 0, in: ctx, rect: CGRect(x: 100, y: 100, width: 100, height: 100))
        #expect(PDFFixtures.luma(ctx, x: 150, y: 120) < 40, "bar scaled into the lower-right quadrant's top half")
        #expect(PDFFixtures.luma(ctx, x: 150, y: 180) > 215)
        #expect(PDFFixtures.luma(ctx, x: 50, y: 50) > 215, "outside the rect is not painted")
    }

    @Test func rotatedPageIsDrawnUpright() throws {
        // 200x100 landscape page with the bar on the top edge, rotated 90 degrees clockwise: the bar ends up at the right.
        let source = try PDFSource(data: PDFFixtures.pdfWithRotation(size: CGSize(width: 200, height: 100), degrees: 90))
        let size = source.size(ofPage: 0)
        let ctx = PDFFixtures.pageContext(size)
        source.draw(pageIndex: 0, in: ctx, rect: CGRect(origin: .zero, size: size))
        #expect(PDFFixtures.luma(ctx, x: Int(size.width) - 5, y: 100) < 40)
        #expect(PDFFixtures.luma(ctx, x: 5, y: 100) > 215)
    }

    @Test func sniffsPDFsAndImagesByContent() {
        #expect(BackgroundKind.sniff(PDFFixtures.pdf(pages: 1)) == .pdf)
        #expect(BackgroundKind.sniff(PDFFixtures.png(width: 4, height: 4)) == .image)
    }

    @Test func fiveHundredPageDocumentOpensQuickly() throws {
        let data = PDFFixtures.pdf(pages: 500)
        let start = Date()
        let source = try PDFSource(data: data)
        _ = source.sizes()
        #expect(source.pageCount == 500)
        #expect(Date().timeIntervalSince(start) < 3, "opening and sizing 500 pages must stay well under the 2-3 s budget")
    }
}

@Suite("Image page source")
struct ImagePageSourceTests {
    @Test func readsSizeAndDrawsIntoARect() throws {
        let source = try ImagePageSource(data: PDFFixtures.png(width: 40, height: 20))
        #expect(source.pixelSize == CGSize(width: 40, height: 20))
        let ctx = PDFFixtures.pageContext(CGSize(width: 100, height: 100))
        source.draw(in: ctx, rect: CGRect(x: 0, y: 0, width: 100, height: 50))
        #expect(PDFFixtures.luma(ctx, x: 50, y: 25) < 200, "red fill is darker than white by luma")
        #expect(PDFFixtures.luma(ctx, x: 50, y: 90) > 250)
    }

    @Test func pageSizeKeepsAspectWithA4LongEdge() {
        #expect(ImagePageSource.pageSize(forPixels: CGSize(width: 4000, height: 3000)) == CGSize(width: 842, height: 632))
        #expect(ImagePageSource.pageSize(forPixels: CGSize(width: 100, height: 400)) == CGSize(width: 211, height: 842))
    }

    @Test func rejectsNonImages() {
        #expect(throws: PdfIOError.unreadableImage("note.txt")) { try ImagePageSource(data: Data("hello".utf8), name: "note.txt") }
    }
}

@Suite("Sort key spread")
struct SortKeySpreadTests {
    @Test func producesAscendingKeysBetweenTheBounds() {
        let keys = SortKey.spread(500, between: "F", and: "G")
        #expect(keys.count == 500)
        #expect(keys == keys.sorted())
        #expect(Set(keys).count == 500)
        #expect(keys.first! > "F" && keys.last! < "G")
        #expect(keys.map(\.count).max()! < 20, "bisection keeps keys short")
    }

    @Test func handlesEmptyAndOpenBounds() {
        #expect(SortKey.spread(0, between: nil, and: nil).isEmpty)
        let open = SortKey.spread(5, between: nil, and: nil)
        #expect(open == open.sorted() && Set(open).count == 5)
    }
}
