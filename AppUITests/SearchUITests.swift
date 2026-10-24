import XCTest

final class SearchUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    // MARK: Helpers

    @MainActor private func openNotebook(_ scenario: UITestScenario, title: String) -> XCUIApplication {
        let app = AppLauncher.launch(scenario)
        let notebook = app.buttons["item.\(title)"]
        XCTAssertTrue(notebook.waitForExistence(timeout: 10), "\(title) should be in the library")
        notebook.tap()
        XCTAssertTrue(app.buttons["editor.pageIndicator"].waitForExistence(timeout: 10), "editor should open")
        return app
    }

    @MainActor private func type(_ text: String, intoSearchOf app: XCUIApplication) {
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5), "search field")
        field.tap()
        field.typeText(text)
    }

    @MainActor private func openNavigator(_ app: XCUIApplication, tab: String) {
        app.buttons["editor.pages"].tap()
        let tabs = app.segmentedControls["editor.navigator.tabs"]
        XCTAssertTrue(tabs.waitForExistence(timeout: 5), "navigator tabs")
        tabs.buttons[tab].tap()
    }

    @MainActor private func goToPage(_ number: Int, in app: XCUIApplication) {
        app.buttons["editor.pages"].tap()
        let thumb = app.descendants(matching: .any)["editor.thumb.\(number)"]
        XCTAssertTrue(thumb.waitForExistence(timeout: 5))
        thumb.tap()
        XCTAssertTrue(app.buttons["editor.pageIndicator"].waitForExistence(timeout: 5))
    }

    // MARK: Library search

    @MainActor func testLibrarySearchFindsANotebookByTitleAndOpensIt() {
        let app = AppLauncher.launch(.libraryBasic)
        let search = app.buttons["sidebar.search"].exists ? app.buttons["sidebar.search"] : app.staticTexts["sidebar.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 10), "sidebar search entry")
        search.tap()
        type("Phys", intoSearchOf: app)
        let result = app.buttons["search.result.title.Physics 101"]
        XCTAssertTrue(result.waitForExistence(timeout: 10), "title result")
        XCTAssertFalse(app.buttons["search.result.title.Recipes"].exists)
        result.tap()
        XCTAssertTrue(app.descendants(matching: .any)["editor.root"].waitForExistence(timeout: 10), "opening a result opens the notebook")
    }

    @MainActor func testLibrarySearchWithNoMatchShowsAnEmptyState() {
        let app = AppLauncher.launch(.libraryBasic)
        let search = app.buttons["sidebar.search"].exists ? app.buttons["sidebar.search"] : app.staticTexts["sidebar.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        type("zzzzqq", intoSearchOf: app)
        XCTAssertTrue(app.staticTexts["No Results for “zzzzqq”"].waitForExistence(timeout: 10)
                      || app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'zzzzqq'")).firstMatch.waitForExistence(timeout: 5))
    }

    // MARK: Notebook search

    @MainActor func testSearchingPdfTextInsideANotebookJumpsToThePage() {
        let app = openNotebook(.pdfNotebook, title: "Fixture PDF")
        app.buttons["search.notebook.button"].tap()
        type("2", intoSearchOf: app)
        let result = app.buttons["search.notebook.result.2"]
        XCTAssertTrue(result.waitForExistence(timeout: 15), "PDF text of page 2 should be searchable")
        XCTAssertFalse(app.buttons["search.notebook.result.1"].exists)
        result.tap()
        let indicator = app.buttons["editor.pageIndicator"]
        XCTAssertTrue(indicator.waitForExistence(timeout: 5))
        XCTAssertEqual(indicator.label, "Page 2 of 3")
    }

    // MARK: Bookmarks

    @MainActor func testBookmarkingAPageListsItInTheBookmarksTab() {
        let app = openNotebook(.notebookWith3Pages, title: "Three Pages")
        goToPage(2, in: app)
        let bookmark = app.buttons["search.bookmark"]
        XCTAssertTrue(bookmark.waitForExistence(timeout: 5))
        bookmark.tap()
        openNavigator(app, tab: "Bookmarks")
        XCTAssertTrue(app.descendants(matching: .any)["search.bookmark.row.2"].waitForExistence(timeout: 5), "page 2 is bookmarked")
    }

    @MainActor func testBookmarkTabJumpsToTheBookmarkedPageAndToggleRemovesIt() {
        let app = openNotebook(.notebookWith3Pages, title: "Three Pages")
        goToPage(3, in: app)
        app.buttons["search.bookmark"].tap()
        goToPage(1, in: app)
        openNavigator(app, tab: "Bookmarks")
        let row = app.descendants(matching: .any)["search.bookmark.row.3"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        let indicator = app.buttons["editor.pageIndicator"]
        XCTAssertTrue(indicator.waitForExistence(timeout: 5))
        XCTAssertEqual(indicator.label, "Page 3 of 3")

        app.buttons["search.bookmark"].tap()          // second tap removes it
        openNavigator(app, tab: "Bookmarks")
        XCTAssertTrue(app.staticTexts["No Bookmarks"].waitForExistence(timeout: 5))
    }

    // MARK: Outline

    @MainActor func testOutlineEntryJumpsBackToItsPage() {
        let app = openNotebook(.notebookWith3Pages, title: "Three Pages")
        goToPage(2, in: app)
        app.buttons["editor.more"].tap()
        let add = app.buttons["editor.menu.search.addOutline"]
        XCTAssertTrue(add.waitForExistence(timeout: 5), "menu item to add an outline entry")
        add.tap()
        let title = app.textFields["search.outline.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        title.clearAndType("Chapter two")
        app.buttons["search.outline.save"].tap()

        goToPage(1, in: app)
        openNavigator(app, tab: "Outline")
        let row = app.descendants(matching: .any)["search.outline.row.Chapter two"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), "the new entry is listed")
        row.tap()
        let indicator = app.buttons["editor.pageIndicator"]
        XCTAssertTrue(indicator.waitForExistence(timeout: 5))
        XCTAssertEqual(indicator.label, "Page 2 of 3")
    }
}

private extension XCUIElement {
    func clearAndType(_ text: String) {
        if let current = value as? String, !current.isEmpty, current != "Title" {
            typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        }
        typeText(text)
    }
}
