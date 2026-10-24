import XCTest
@testable import SheafnoteCore

final class HighlightGeometryTests: XCTestCase {
    private let line = RecognizedLine(text: "buy milk now", confidence: 1,
                                      boundingBox: CGRect(x: 0.1, y: 0.7, width: 0.6, height: 0.1))

    func testFlipsToTopLeftOriginAndNarrowsToTheWord() {
        let rects = HighlightGeometry.rects(for: ["milk"], in: [line], padding: 0)
        XCTAssertEqual(rects.count, 1)
        let r = rects[0]
        XCTAssertEqual(r.minY, 0.2, accuracy: 1e-9)          // 1 - (0.7 + 0.1)
        XCTAssertEqual(r.height, 0.1, accuracy: 1e-9)
        XCTAssertEqual(r.minX, 0.1 + 0.6 * 4.0 / 12.0, accuracy: 1e-9)
        XCTAssertEqual(r.width, 0.6 * 4.0 / 12.0, accuracy: 1e-9)
    }

    func testPrefixAndMultipleHitsAndMissingTerms() {
        let two = RecognizedLine(text: "milk and more milk", confidence: 1, boundingBox: CGRect(x: 0, y: 0, width: 1, height: 0.1))
        XCTAssertEqual(HighlightGeometry.rects(for: ["mil"], in: [two], padding: 0).count, 2)
        XCTAssertTrue(HighlightGeometry.rects(for: ["cheese"], in: [two], padding: 0).isEmpty)
        XCTAssertTrue(HighlightGeometry.rects(for: [], in: [two], padding: 0).isEmpty)
    }

    func testPaddingGrowsRectsButStaysInsideThePage() {
        let edge = RecognizedLine(text: "milk", confidence: 1, boundingBox: CGRect(x: 0, y: 0.9, width: 1, height: 0.1))
        let r = HighlightGeometry.rects(for: ["milk"], in: [edge], padding: 0.01)[0]
        XCTAssertGreaterThanOrEqual(r.minX, 0)
        XCTAssertGreaterThanOrEqual(r.minY, 0)
        XCTAssertLessThanOrEqual(r.maxX, 1)
        XCTAssertLessThanOrEqual(r.maxY, 1)
    }

    func testElementFramesBecomeUnitRects() {
        let r = HighlightGeometry.unitRect(of: CGRect(x: 100, y: 200, width: 50, height: 20), pageSize: CGSize(width: 200, height: 400))
        XCTAssertEqual(r, CGRect(x: 0.5, y: 0.5, width: 0.25, height: 0.05))
        XCTAssertEqual(HighlightGeometry.unitRect(of: .zero, pageSize: .zero), .zero)
    }
}
