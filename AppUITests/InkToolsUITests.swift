import XCTest

/// Draw a stroke, select it with the lasso, move it, delete it, undo. XCUITest can only drive straight drags, so the
/// lasso is exercised by tapping the stroke (the freeform loop is covered by unit tests on `LassoTool.finish`).
final class InkToolsUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    // MARK: Helpers

    @MainActor private func openNotebook() -> XCUIApplication {
        let app = AppLauncher.launch(.notebookWith3Pages)
        let notebook = app.buttons["item.Three Pages"]
        XCTAssertTrue(notebook.waitForExistence(timeout: 10))
        notebook.tap()
        XCTAssertTrue(page(in: app).waitForExistence(timeout: 10), "editor page 1 should appear")
        return app
    }

    @MainActor private func page(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["editor.page.1"]
    }

    @MainActor private func drawStroke(on page: XCUIElement) {
        let start = page.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.2))
        let end = page.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.28))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    @MainActor private func waitForValue(_ element: XCUIElement, containing text: String, timeout: TimeInterval = 8) -> Bool {
        let predicate = NSPredicate(format: "value CONTAINS %@", text)
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: timeout) == .completed
    }

    // MARK: Tests

    @MainActor func testShapesAndLassoJoinTheToolRowWithTheirOptions() {
        let app = openNotebook()
        for id in ["editor.tool.shapes", "editor.tool.lasso"] {
            XCTAssertTrue(app.buttons[id].waitForExistence(timeout: 5), "\(id) should exist")
        }
        app.buttons["editor.tool.lasso"].tap()
        XCTAssertTrue(app.buttons["inktools.lasso.selectAll"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["inktools.lasso.paste"].exists)
        app.buttons["editor.tool.shapes"].tap()
        XCTAssertTrue(app.buttons["inktools.shapes.mode"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["inktools.shapes.fill"].exists)
        app.buttons["editor.tool.highlighter"].tap()
        XCTAssertTrue(app.buttons["inktools.highlighter.straight"].waitForExistence(timeout: 5), "the highlighter gets its straight-line switch")
    }

    @MainActor func testLassoSelectsMovesDeletesAndUndoRestores() {
        let app = openNotebook()
        let canvas = page(in: app)
        XCTAssertTrue(waitForValue(canvas, containing: "0 strokes"))
        drawStroke(on: canvas)
        XCTAssertTrue(waitForValue(canvas, containing: "1 stroke"))

        app.buttons["editor.tool.lasso"].tap()
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.425, dy: 0.24)).tap()
        let delete = app.buttons["editor.selection.ink.delete"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5), "tapping the stroke selects it and shows the action menu")
        XCTAssertTrue(app.buttons["editor.selection.ink.copy"].exists)
        XCTAssertTrue(app.buttons["editor.selection.ink.style"].exists)

        // Move: drag inside the selection frame.
        let from = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.425, dy: 0.24))
        let to = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.425, dy: 0.5))
        from.press(forDuration: 0.1, thenDragTo: to)
        XCTAssertTrue(waitForValue(canvas, containing: "1 stroke"), "moving keeps the stroke")
        XCTAssertTrue(app.buttons["editor.undo"].isEnabled)

        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        delete.tap()
        XCTAssertTrue(waitForValue(canvas, containing: "0 strokes"), "delete removes the selected stroke")

        app.buttons["editor.undo"].tap()
        XCTAssertTrue(waitForValue(canvas, containing: "1 stroke"), "undo brings the stroke back")
    }

    @MainActor func testShapesToolDrawsADraggedRectangleThatUndoRemoves() {
        let app = openNotebook()
        let canvas = page(in: app)
        app.buttons["editor.tool.shapes"].tap()
        app.buttons["inktools.shapes.mode"].tap()
        app.buttons["Rectangle"].tap()
        let start = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.2))
        let end = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.4))
        start.press(forDuration: 0.05, thenDragTo: end)
        // A new shape is selected straight away, so the selection's action menu appears.
        XCTAssertTrue(app.buttons["editor.selection.ink.delete"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["editor.selection.ink.style"].exists)
        app.buttons["editor.undo"].tap()
        XCTAssertFalse(app.buttons["editor.selection.ink.delete"].waitForExistence(timeout: 2), "undo removes the shape and its selection")
    }
}
