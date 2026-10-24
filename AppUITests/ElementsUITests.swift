import XCTest

final class ElementsUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    // MARK: Helpers

    @MainActor private func openNotebook() -> XCUIApplication {
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

    @MainActor private func element(_ id: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    @MainActor private func selectTapeTool(_ app: XCUIApplication) {
        app.buttons["editor.tool.more"].tap()
        let item = app.buttons["Study Tape"]
        XCTAssertTrue(item.waitForExistence(timeout: 5), "the more menu lists the tape tool")
        item.tap()
        XCTAssertTrue(app.buttons["elements.tape.toggleAll"].waitForExistence(timeout: 5))
    }

    @MainActor private func layTape(on app: XCUIApplication) {
        let canvas = page(1, in: app)
        let start = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5))
        let end = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.53))
        start.press(forDuration: 0.1, thenDragTo: end)
    }

    @MainActor private func waitForValue(_ element: XCUIElement, _ value: String, timeout: TimeInterval = 8) -> Bool {
        let predicate = NSPredicate(format: "value == %@", value)
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: timeout) == .completed
    }

    // MARK: Tests

    @MainActor func testTheToolRowOffersTextAndElementTools() {
        let app = openNotebook()
        XCTAssertTrue(app.buttons["editor.tool.text"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["editor.tool.element"].exists)
        app.buttons["editor.tool.text"].tap()
        XCTAssertTrue(app.buttons["elements.text.bold"].waitForExistence(timeout: 5), "the text tool shows its style options")
        app.buttons["editor.tool.element"].tap()
        XCTAssertTrue(app.buttons["elements.insert.browser"].waitForExistence(timeout: 5), "the element tool shows where to insert from")
        XCTAssertTrue(app.buttons["elements.insert.files"].exists)
        XCTAssertTrue(app.buttons["elements.insert.photos"].exists || app.otherElements["elements.insert.photos"].exists)
    }

    @MainActor func testAddingATextBoxByTypingOnThePage() {
        let app = openNotebook()
        app.buttons["editor.tool.text"].tap()
        XCTAssertTrue(app.buttons["elements.text.bold"].waitForExistence(timeout: 5))
        page(1, in: app).coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.3)).tap()
        let field = app.textViews["Text box"]
        XCTAssertTrue(field.waitForExistence(timeout: 8), "tapping the page with the text tool opens a text box")
        field.typeText("Hello Sheafnote")
        // The first tap away finishes editing and the box stays on the page.
        page(1, in: app).coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.08)).tap()
        let box = element("elements.text", in: app)
        XCTAssertTrue(box.waitForExistence(timeout: 8), "the typed text is a text element afterwards")
        XCTAssertEqual(box.label, "Hello Sheafnote")
    }

    @MainActor func testAddingAStickerFromTheBrowser() {
        let app = openNotebook()
        app.buttons["editor.tool.element"].tap()
        app.buttons["elements.insert.browser"].tap()
        let star = app.buttons["elements.sticker.star"]
        XCTAssertTrue(star.waitForExistence(timeout: 8), "the sticker browser lists the built-in stickers")
        star.tap()
        let sticker = element("elements.sticker", in: app)
        XCTAssertTrue(sticker.waitForExistence(timeout: 8), "the sticker is on the page")
        XCTAssertEqual(sticker.label, "Star")
        XCTAssertTrue(app.buttons["elements.image.crop"].exists == false, "a sticker has no crop button")
        XCTAssertTrue(app.buttons["editor.selection.elements.save"].waitForExistence(timeout: 5), "the new sticker is selected and can be saved")
    }

    @MainActor func testSavedElementsTabListsASavedSticker() {
        let app = openNotebook()
        app.buttons["editor.tool.element"].tap()
        app.buttons["elements.insert.browser"].tap()
        app.buttons["elements.sticker.heart"].tap()
        let save = app.buttons["editor.selection.elements.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 8))
        save.tap()
        let name = app.textFields["elements.save.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 8))
        app.buttons["elements.save.confirm"].tap()
        app.buttons["elements.insert.browser"].tap()
        app.segmentedControls["elements.browser.tabs"].buttons["Saved"].tap()
        XCTAssertTrue(app.staticTexts["Untitled element"].waitForExistence(timeout: 8), "the saved element is listed")
    }

    @MainActor func testStudyTapeCoversTogglesAndHidesAll() {
        let app = openNotebook()
        selectTapeTool(app)
        layTape(on: app)
        let tape = element("elements.tape", in: app)
        XCTAssertTrue(tape.waitForExistence(timeout: 8), "dragging with the tape tool lays tape")
        XCTAssertTrue(waitForValue(tape, "Covering"))
        // Tap to reveal, tap again to cover.
        tape.tap()
        XCTAssertTrue(waitForValue(tape, "Revealed"))
        tape.tap()
        XCTAssertTrue(waitForValue(tape, "Covering"))
        // "Hide all" turns into "Show all" once everything is covering, and back.
        let toggleAll = app.buttons["elements.tape.toggleAll"]
        XCTAssertEqual(toggleAll.label, "Show all")
        toggleAll.tap()
        XCTAssertTrue(waitForValue(tape, "Revealed"))
        XCTAssertEqual(toggleAll.label, "Hide all")
        toggleAll.tap()
        XCTAssertTrue(waitForValue(tape, "Covering"))
    }
}
