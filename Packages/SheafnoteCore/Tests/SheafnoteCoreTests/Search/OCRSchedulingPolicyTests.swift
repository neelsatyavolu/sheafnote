import XCTest
@testable import SheafnoteCore

final class OCRSchedulingPolicyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 10_000)

    private func state(ink: String = "h1", ocr: String = "", strokes: Int = 3, text: Bool = false,
                        age: TimeInterval = 60) -> OCRPageState {
        OCRPageState(pageID: UUID(), notebookID: UUID(), inkHash: ink, ocrInkHash: ocr, strokeCount: strokes,
                     hasRecognizedText: text, modifiedAt: now.addingTimeInterval(-age))
    }

    func testRecognizesOnlyWhenInkChangedSinceLastOCR() {
        XCTAssertEqual(OCRSchedulingPolicy.action(for: state(ink: "a", ocr: "")), .recognize)
        XCTAssertEqual(OCRSchedulingPolicy.action(for: state(ink: "b", ocr: "a")), .recognize)
        XCTAssertEqual(OCRSchedulingPolicy.action(for: state(ink: "a", ocr: "a")), .skip)
    }

    func testBlankPagesAreSkipped() {
        XCTAssertEqual(OCRSchedulingPolicy.action(for: state(ink: "", ocr: "", strokes: 0)), .skip)
    }

    func testClearedPageDropsStaleTextWithoutRunningVision() {
        XCTAssertEqual(OCRSchedulingPolicy.action(for: state(ink: "empty", ocr: "old", strokes: 0, text: true)), .clearText)
        XCTAssertEqual(OCRSchedulingPolicy.action(for: state(ink: "empty", ocr: "old", strokes: 0, text: false)), .skip)
    }

    func testPlanSkipsPagesStillBeingWrittenOn() {
        let writing = state(age: 1)
        let settled = state(age: 30)
        let plan = OCRSchedulingPolicy.plan([writing, settled], now: now, limit: 10)
        XCTAssertEqual(plan.map(\.pageID), [settled.pageID])
    }

    func testPlanIsNewestFirstAndLimited() {
        let old = state(age: 500)
        let mid = state(age: 200)
        let new = state(age: 100)
        let plan = OCRSchedulingPolicy.plan([old, new, mid], now: now, limit: 2)
        XCTAssertEqual(plan.map(\.pageID), [new.pageID, mid.pageID])
        XCTAssertEqual(plan.map(\.action), [.recognize, .recognize])
    }

    func testPlanOmitsUpToDatePages() {
        XCTAssertTrue(OCRSchedulingPolicy.plan([state(ink: "a", ocr: "a")], now: now, limit: 5).isEmpty)
    }
}
