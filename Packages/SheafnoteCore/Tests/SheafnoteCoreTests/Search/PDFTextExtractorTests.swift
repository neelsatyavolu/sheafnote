import CoreGraphics
import CoreText
import XCTest
@testable import SheafnoteCore

final class PDFTextExtractorTests: XCTestCase {
    static func makePDF(pages: [String]) -> Data {
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        let consumer = CGDataConsumer(data: data)!
        let ctx = CGContext(consumer: consumer, mediaBox: &box, nil)!
        for text in pages {
            ctx.beginPDFPage(nil)
            let font = CTFontCreateWithName("Helvetica" as CFString, 32, nil)
            let attributed = NSAttributedString(string: text, attributes: [.font: font])
            let line = CTLineCreateWithAttributedString(attributed)
            ctx.textPosition = CGPoint(x: 72, y: 700)
            CTLineDraw(line, ctx)
            ctx.endPDFPage()
        }
        ctx.closePDF()
        return data as Data
    }

    func testExtractsOneStringPerPage() throws {
        let texts = try PDFTextExtractor.pageTexts(from: Self.makePDF(pages: ["Entropy chapter", "Enthalpy chapter"]))
        XCTAssertEqual(texts.count, 2)
        XCTAssertTrue(texts[0].contains("Entropy"))
        XCTAssertTrue(texts[1].contains("Enthalpy"))
    }

    func testGarbageThrowsUnreadable() {
        XCTAssertThrowsError(try PDFTextExtractor.pageTexts(from: Data("not a pdf".utf8))) {
            XCTAssertEqual($0 as? PDFTextError, .unreadable)
        }
    }

    func testMatchRectsLandOnTheRightPageNearTheTop() throws {
        let data = Self.makePDF(pages: ["plain", "find the Entropy here"])
        XCTAssertTrue(try PDFTextExtractor.matchRects(in: data, pageIndex: 0, terms: ["entropy"]).isEmpty)
        let rects = try PDFTextExtractor.matchRects(in: data, pageIndex: 1, terms: ["entropy"])
        XCTAssertEqual(rects.count, 1)
        let r = rects[0]
        XCTAssertLessThan(r.minY, 0.2)           // drawn near the top of the page
        XCTAssertGreaterThan(r.minX, 0.1)
        XCTAssertGreaterThan(r.width, 0)
    }

    func testMatchRectsOutOfRangePageIsEmpty() throws {
        XCTAssertTrue(try PDFTextExtractor.matchRects(in: Self.makePDF(pages: ["a"]), pageIndex: 4, terms: ["a"]).isEmpty)
    }
}
