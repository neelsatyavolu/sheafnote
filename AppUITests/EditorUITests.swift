import XCTest

final class EditorUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    // MARK: Helpers

    @MainActor private func openThreePages() -> XCUIApplication {
        let app = AppLauncher.launch(.notebookWith3Pages)
        let notebook = app.buttons["item.Three Pages"]
        XCTAssertTrue(notebook.waitForExistence(timeout: 10))
        notebook.tap()
        XCTAssertTrue(page(1, in: app).waitForExistence(timeout: 10), "editor page 1 should appear")
        return app
    }

    @MainActor private func page(_ number: Int, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["editor.page.\(number)"]
    }

    @MainActor private func drawStroke(on element: XCUIElement) {
        let start = element.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.2))
        let end = element.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.28))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    @MainActor private func strokeValue(_ element: XCUIElement) -> String { (element.value as? String) ?? "" }

    @MainActor private func waitForValue(_ element: XCUIElement, containing text: String, timeout: TimeInterval = 8) -> Bool {
        let predicate = NSPredicate(format: "value CONTAINS %@", text)
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: timeout) == .completed
    }

    @MainActor private func openMore(_ app: XCUIApplication) {
        app.buttons["editor.more"].tap()
    }

    // MARK: Tests

    @MainActor func testOpeningANotebookShowsTheEditorChrome() {
        let app = openThreePages()
        for id in ["editor.back", "editor.pages", "editor.undo", "editor.redo", "editor.more",
                   "editor.tool.pen", "editor.tool.eraser", "editor.tool.highlighter"] {
            XCTAssertTrue(app.buttons[id].waitForExistence(timeout: 5), "\(id) should exist")
        }
        XCTAssertTrue(app.buttons["editor.options.addColor"].exists, "the pen's options row shows presets")
        XCTAssertTrue(app.buttons["editor.pageIndicator"].exists)
        XCTAssertEqual(app.buttons["editor.pageIndicator"].label, "Page 1 of 3")
    }

    @MainActor func testWritingCreatesAStrokeThatUndoAndRedoToggle() {
        let app = openThreePages()
        let canvas = page(1, in: app)
        XCTAssertTrue(waitForValue(canvas, containing: "0 strokes"), "value=\(strokeValue(canvas)) \(canvas.debugDescription)")
        drawStroke(on: canvas)
        XCTAssertTrue(waitForValue(canvas, containing: "1 stroke"), "got \(strokeValue(canvas))")
        app.buttons["editor.undo"].tap()
        XCTAssertTrue(waitForValue(canvas, containing: "0 strokes"))
        app.buttons["editor.redo"].tap()
        XCTAssertTrue(waitForValue(canvas, containing: "1 stroke"))
    }

    @MainActor func testSwitchingToolsChangesTheOptionsRow() {
        let app = openThreePages()
        app.buttons["editor.tool.eraser"].tap()
        XCTAssertTrue(app.segmentedControls["editor.eraser.mode"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["editor.tool.eraser"].isSelected)
        app.buttons["editor.tool.highlighter"].tap()
        XCTAssertTrue(app.buttons["editor.options.addColor"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.segmentedControls["editor.eraser.mode"].exists)
        app.buttons["editor.tool.pen"].tap()
        XCTAssertTrue(app.buttons["editor.options.inkType"].waitForExistence(timeout: 5), "only the pen has an ink type menu")
    }

    @MainActor func testSelectingAColorPresetAndWidth() {
        let app = openThreePages()
        let colors = app.buttons.matching(identifier: "editor.options.color")
        XCTAssertEqual(colors.count, 4)
        colors.element(boundBy: 1).tap()
        XCTAssertTrue(colors.element(boundBy: 1).isSelected)
        app.buttons["editor.options.width.2"].tap()
        XCTAssertTrue(app.buttons["editor.options.width.2"].isSelected)
    }

    @MainActor func testAddPageFromTheMenu() {
        let app = openThreePages()
        openMore(app)
        app.buttons["Add Page…"].tap()
        let confirm = app.buttons["editor.addPage.confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        let indicator = app.buttons["editor.pageIndicator"]
        XCTAssertTrue(indicator.waitForExistence(timeout: 5))
        XCTAssertEqual(indicator.label, "Page 2 of 4")
    }

    @MainActor func testNavigatorShowsThumbnailsAndJumpsToAPage() {
        let app = openThreePages()
        app.buttons["editor.pages"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["editor.thumb.3"].waitForExistence(timeout: 8))
        app.descendants(matching: .any)["editor.thumb.3"].tap()
        let indicator = app.buttons["editor.pageIndicator"]
        XCTAssertTrue(indicator.waitForExistence(timeout: 5))
        XCTAssertEqual(waitFor(indicator, label: "Page 3 of 3"), "Page 3 of 3")
    }

    // Drag-to-reorder is not covered here: XCUITest cannot reliably drive SwiftUI drag and drop. The move logic
    // (fractional keys, undo) is covered by PageOperationTests.

    @MainActor func testPencilOnlyModeStopsFingerDrawing() {
        let app = openThreePages()
        openMore(app)
        app.buttons["Draw with Finger"].tap()
        let canvas = page(1, in: app)
        drawStroke(on: canvas)
        sleep(1)
        XCTAssertTrue(strokeValue(canvas).contains("0 strokes"), "a finger must not draw in Pencil-only mode, got \(strokeValue(canvas))")
    }

    @MainActor func testHorizontalPagingMovesToTheNextPage() {
        let app = openThreePages()
        openMore(app)
        app.buttons["Draw with Finger"].tap()   // one finger scrolls in Pencil-only mode
        openMore(app)
        app.buttons["Horizontal Pages"].tap()
        let indicator = app.buttons["editor.pageIndicator"]
        XCTAssertTrue(indicator.waitForExistence(timeout: 5))
        XCTAssertEqual(indicator.label, "Page 1 of 3")
        app.swipeLeft()
        XCTAssertEqual(waitFor(indicator, label: "Page 2 of 3"), "Page 2 of 3")
    }

    @MainActor func testChangePageTemplateSheetApplies() {
        let app = openThreePages()
        openMore(app)
        app.buttons["Page Template…"].tap()
        let apply = app.buttons["editor.template.applyPage"]
        XCTAssertTrue(apply.waitForExistence(timeout: 5))
        app.buttons["paper.category.grid"].tap()
        apply.tap()
        XCTAssertTrue(page(1, in: app).waitForExistence(timeout: 5))
        XCTAssertFalse(apply.exists)
    }

    @MainActor func testBackReturnsToTheLibrary() {
        let app = openThreePages()
        app.buttons["editor.back"].tap()
        XCTAssertTrue(app.buttons["item.Three Pages"].waitForExistence(timeout: 5))
    }

    @MainActor func testWritingSurvivesLeavingAndReopening() {
        let app = openThreePages()
        drawStroke(on: page(1, in: app))
        XCTAssertTrue(waitForValue(page(1, in: app), containing: "1 stroke"))
        app.buttons["editor.back"].tap()
        let notebook = app.buttons["item.Three Pages"]
        XCTAssertTrue(notebook.waitForExistence(timeout: 5))
        notebook.tap()
        XCTAssertTrue(waitForValue(page(1, in: app), containing: "1 stroke"), "ink must be saved when the editor closes")
    }

    // MARK: Polling

    /// Returns the label once it equals `label` (or the last seen label after a timeout).
    @MainActor private func waitFor(_ element: XCUIElement, label: String, timeout: TimeInterval = 8) -> String {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.label == label { return label }
            usleep(200_000)
        }
        return element.label
    }
}
