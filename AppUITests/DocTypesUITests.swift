import XCTest

final class DocTypesUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    // MARK: Helpers

    @MainActor private func launch(_ scenario: UITestScenario, authFails: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestMode", "1", "-UITestScenario", scenario.rawValue, "-AppleLanguages", "(en)"]
        if authFails { app.launchArguments += ["-UITestAuthFails", "1"] }
        app.launch()
        return app
    }

    @MainActor private func create(_ item: String, in app: XCUIApplication) {
        let menu = app.buttons["library.newMenu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 10))
        menu.tap()
        let entry = app.buttons["library.new.\(item)"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5), "New menu should offer \(item)")
        entry.tap()
    }

    @MainActor private func strokeValue(_ element: XCUIElement) -> String { (element.value as? String) ?? "" }

    @MainActor private func waitForValue(_ element: XCUIElement, containing text: String, timeout: TimeInterval = 8) -> Bool {
        let predicate = NSPredicate(format: "value CONTAINS %@", text)
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: timeout) == .completed
    }

    // MARK: Whiteboard

    @MainActor func testCreateWhiteboardDrawAndReopen() {
        let app = launch(.empty)
        create("whiteboard", in: app)
        let canvas = app.descendants(matching: .any)["editor.page.1"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 10), "creating a whiteboard opens the editor")
        XCTAssertTrue(app.buttons["editor.tool.pen"].exists, "whiteboards have the same tool row")
        XCTAssertTrue(waitForValue(canvas, containing: "0 strokes"), "got \(strokeValue(canvas))")
        let start = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.3))
        let end = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
        start.press(forDuration: 0.05, thenDragTo: end)
        XCTAssertTrue(waitForValue(canvas, containing: "1 stroke"), "got \(strokeValue(canvas))")
        app.buttons["editor.back"].tap()
        let board = app.buttons["item.Untitled Whiteboard"]
        XCTAssertTrue(board.waitForExistence(timeout: 5))
        board.tap()
        XCTAssertTrue(waitForValue(app.descendants(matching: .any)["editor.page.1"], containing: "1 stroke"),
                      "ink is saved when the whiteboard closes")
    }

    // MARK: Text document

    @MainActor func testCreateTextDocumentTypeChecklistAndReopen() {
        let app = launch(.empty)
        create("textDocument", in: app)
        XCTAssertTrue(app.otherElements["textdoc.root"].waitForExistence(timeout: 10) || app.textFields["textdoc.field.0"].waitForExistence(timeout: 10))
        let first = app.textFields["textdoc.field.0"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        app.buttons["textdoc.style"].tap()
        let checklist = app.buttons["textdoc.style.checklist"]
        XCTAssertTrue(checklist.waitForExistence(timeout: 8), "style menu lists Checklist")
        sleep(1)  // let the menu finish animating before tapping
        checklist.tap()
        first.tap()
        first.typeText("Milk\nEggs")
        let second = app.textFields["textdoc.field.1"]
        XCTAssertTrue(second.waitForExistence(timeout: 5), "return starts a new checklist item")
        let box = app.buttons["textdoc.check.0"]
        XCTAssertTrue(box.exists, "list items are checklist items")
        box.tap()
        XCTAssertEqual(box.value as? String, "Checked")
        app.buttons["textdoc.back"].tap()
        let doc = app.buttons["item.Untitled Text Document"]
        XCTAssertTrue(doc.waitForExistence(timeout: 5))
        doc.tap()
        let reopened = app.textFields["textdoc.field.0"]
        XCTAssertTrue(reopened.waitForExistence(timeout: 5))
        XCTAssertEqual(reopened.value as? String, "Milk")
        XCTAssertEqual(app.buttons["textdoc.check.0"].value as? String, "Checked", "checked state is saved")
        XCTAssertEqual(app.textFields["textdoc.field.1"].value as? String, "Eggs")
    }

    // MARK: Lock

    @MainActor private func lockRecipes(in app: XCUIApplication) {
        let recipes = app.buttons["item.Recipes"]
        XCTAssertTrue(recipes.waitForExistence(timeout: 10))
        recipes.press(forDuration: 1.0)
        app.buttons["Lock or Unlock"].tap()
    }

    @MainActor func testLockedNotebookStaysClosedWhenAuthenticationFails() {
        let app = launch(.libraryBasic, authFails: true)
        lockRecipes(in: app)
        app.buttons["item.Recipes"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["lock.notebook"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["lock.message"].waitForExistence(timeout: 5), "a failed attempt explains itself")
        XCTAssertFalse(app.buttons["editor.back"].exists, "the editor is never built for a locked notebook")
        app.buttons["lock.back"].tap()
        XCTAssertTrue(app.buttons["item.Recipes"].waitForExistence(timeout: 5), "back returns to the library with the notebook intact")
    }

    @MainActor func testLockedNotebookOpensAfterAuthentication() {
        let app = launch(.libraryBasic)
        lockRecipes(in: app)
        app.buttons["item.Recipes"].tap()
        XCTAssertTrue(app.buttons["editor.back"].waitForExistence(timeout: 10), "a successful unlock opens the editor")
    }

    @MainActor func testAppLockSettingsSectionIsListed() {
        let app = launch(.empty)
        app.openLibrarySection("library.settings")
        XCTAssertTrue(app.staticTexts["App Lock"].waitForExistence(timeout: 5))
    }
}
