import XCTest
@testable import SheafnoteCore

@MainActor
final class PageTextStoreTests: XCTestCase {
    private var fixture: StoreFixture?
    private func setup() throws -> (StoreFixture, Notebook, Page, PageTextStore) {
        let f = try StoreFixture()
        fixture = f
        let nb = try f.notebook()
        let page = try XCTUnwrap(f.pages.orderedPages(of: nb.id).first)
        return (f, nb, page, PageTextStore(context: f.context))
    }

    func testStatesFlagPagesWithNewInk() throws {
        let (f, _, page, store) = try setup()
        try f.pages.saveInk(pageID: page.id, drawingData: Data([1, 2]), strokeIDs: [StrokeID(rawValue: "s1")])
        let states = try store.ocrStates()
        XCTAssertEqual(states.count, 1)
        XCTAssertEqual(OCRSchedulingPolicy.action(for: states[0]), .recognize)
    }

    func testStoringTextMarksPageDirtyAndStopsFurtherOCR() throws {
        let (f, _, page, store) = try setup()
        try f.pages.saveInk(pageID: page.id, drawingData: Data([1]), strokeIDs: [StrokeID(rawValue: "s1")])
        page.syncDirty = false
        page.dirtyFields = []
        XCTAssertTrue(try store.store(text: "hello", forInkHash: page.inkHash, pageID: page.id))
        XCTAssertEqual(page.recognizedText, "hello")
        XCTAssertEqual(page.ocrInkHash, page.inkHash)
        XCTAssertTrue(page.syncDirty)
        XCTAssertTrue(page.dirtyFields.contains("recognizedText"))
        XCTAssertTrue(page.dirtyFields.contains("ocrInkHash"))
        XCTAssertEqual(OCRSchedulingPolicy.action(for: try store.ocrStates()[0]), .skip)
    }

    func testStaleResultIsNotStoredWhenInkChangedMeanwhile() throws {
        let (f, _, page, store) = try setup()
        try f.pages.saveInk(pageID: page.id, drawingData: Data([1]), strokeIDs: [StrokeID(rawValue: "s1")])
        let readHash = page.inkHash
        try f.pages.saveInk(pageID: page.id, drawingData: Data([1, 2]), strokeIDs: [StrokeID(rawValue: "s1"), StrokeID(rawValue: "s2")])
        XCTAssertFalse(try store.store(text: "old", forInkHash: readHash, pageID: page.id))
        XCTAssertEqual(page.recognizedText, "")
    }

    func testClearedInkDropsTextWithoutVision() throws {
        let (f, _, page, store) = try setup()
        try f.pages.saveInk(pageID: page.id, drawingData: Data([1]), strokeIDs: [StrokeID(rawValue: "s1")])
        try store.store(text: "scribble", forInkHash: page.inkHash, pageID: page.id)
        try f.pages.saveInk(pageID: page.id, drawingData: Data([9]), strokeIDs: [])
        let state = try store.ocrStates()[0]
        XCTAssertEqual(OCRSchedulingPolicy.action(for: state), .clearText)
        XCTAssertTrue(try store.clearText(forInkHash: state.inkHash, pageID: page.id))
        XCTAssertEqual(page.recognizedText, "")
        XCTAssertEqual(OCRSchedulingPolicy.action(for: try store.ocrStates()[0]), .skip)
    }

    func testLockedAndDeletedNotebooksAreNotOCRd() throws {
        let (f, nb, page, store) = try setup()
        try f.pages.saveInk(pageID: page.id, drawingData: Data([1]), strokeIDs: [StrokeID(rawValue: "s1")])
        nb.isLocked = true
        try f.context.save()
        XCTAssertTrue(try store.ocrStates().isEmpty)
        nb.isLocked = false
        try f.library.softDelete([.notebook(nb.id)])
        XCTAssertTrue(try store.ocrStates().isEmpty)
    }

    func testInvalidateAllRequeuesPagesButKeepsTheText() throws {
        let (f, _, page, store) = try setup()
        try f.pages.saveInk(pageID: page.id, drawingData: Data([1]), strokeIDs: [StrokeID(rawValue: "s1")])
        try store.store(text: "keep me", forInkHash: page.inkHash, pageID: page.id)
        XCTAssertEqual(try store.invalidateAll(), 1)
        XCTAssertEqual(page.recognizedText, "keep me")
        XCTAssertEqual(OCRSchedulingPolicy.action(for: try store.ocrStates()[0]), .recognize)
    }
}
