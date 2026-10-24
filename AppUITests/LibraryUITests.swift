import XCTest

final class LibraryUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    @MainActor func testCreateNotebookThroughSheetOpensIt() {
        let app = AppLauncher.launch(.empty)
        app.buttons["library.newMenu"].tap()
        app.buttons["library.new.notebook"].tap()
        let title = app.textFields["newNotebook.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        title.typeText("Chemistry")
        app.buttons["paper.category.grid"].tap()
        app.buttons["newNotebook.create"].tap()
        XCTAssertTrue(app.staticTexts["placeholderEditor.title"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["placeholderEditor.title"].label, "Chemistry")
        app.buttons["placeholderEditor.close"].tap()
        XCTAssertTrue(app.buttons["item.Chemistry"].waitForExistence(timeout: 5))
    }

    @MainActor func testCreateFolderAndOpenIt() {
        let app = AppLauncher.launch(.empty)
        app.buttons["library.newMenu"].tap()
        app.buttons["library.new.folder"].tap()
        let name = app.textFields["newFolder.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("School")
        app.buttons["newFolder.create"].tap()
        XCTAssertTrue(app.buttons["item.School"].waitForExistence(timeout: 5))
    }

    @MainActor func testFavoriteThenAppearsInFavorites() {
        let app = AppLauncher.launch(.libraryBasic)
        let recipes = app.buttons["item.Recipes"]
        XCTAssertTrue(recipes.waitForExistence(timeout: 5))
        recipes.press(forDuration: 1.0)
        app.buttons["Add to Favorites"].tap()
        app.buttons["sidebar.favorites"].tap()
        XCTAssertTrue(app.buttons["item.Recipes"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["item.Physics 101"].exists)
    }

    @MainActor func testDeleteThenRestoreFromRecentlyDeleted() {
        let app = AppLauncher.launch(.libraryBasic)
        let recipes = app.buttons["item.Recipes"]
        XCTAssertTrue(recipes.waitForExistence(timeout: 5))
        recipes.press(forDuration: 1.0)
        app.buttons["Delete"].tap()
        XCTAssertFalse(app.buttons["item.Recipes"].waitForExistence(timeout: 2))
        app.buttons["sidebar.recentlyDeleted"].tap()
        let trashed = app.buttons["item.Recipes"]
        XCTAssertTrue(trashed.waitForExistence(timeout: 5))
        trashed.tap()
        app.buttons["library.restore"].tap()
        app.buttons["sidebar.documents"].tap()
        XCTAssertTrue(app.buttons["item.Recipes"].waitForExistence(timeout: 5))
    }

    @MainActor func testMultiSelectDelete() {
        let app = AppLauncher.launch(.libraryBasic)
        XCTAssertTrue(app.buttons["item.Recipes"].waitForExistence(timeout: 5))
        app.buttons["library.viewMenu"].tap()
        app.buttons["library.select"].tap()
        app.buttons["item.Recipes"].tap()
        app.buttons["item.Physics 101"].tap()
        app.buttons["library.bulkDelete"].tap()
        XCTAssertFalse(app.buttons["item.Recipes"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.buttons["item.Physics 101"].exists)
    }
}
