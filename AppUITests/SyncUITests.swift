import XCTest

final class SyncUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    @MainActor private func openSyncSettings(_ app: XCUIApplication) {
        app.openLibrarySection("library.settings")
        let row = app.buttons["settings.sync"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
    }

    @MainActor func testSettingsShowsSyncSectionWithLocalOnlyToggle() {
        let app = AppLauncher.launch(.empty)
        openSyncSettings(app)
        let toggle = app.switches["sync.toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertEqual(toggle.value as? String, "0", "UI tests start in local-only mode")
        XCTAssertTrue(app.buttons["sync.recovered"].exists)
        XCTAssertFalse(app.buttons["sync.syncNow"].isEnabled)
    }

    @MainActor func testTurningSyncOnEnablesSyncNowAndShowsUpToDate() {
        let app = AppLauncher.launch(.libraryBasic)
        openSyncSettings(app)
        let toggle = app.switches["sync.toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.switches.firstMatch.tap()
        XCTAssertEqual(toggle.value as? String, "1")
        XCTAssertTrue(app.buttons["sync.syncNow"].waitForExistence(timeout: 5))
        let status = app.descendants(matching: .any)["sync.status"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
    }

    @MainActor func testRecoveredPagesScreenIsEmptyByDefault() {
        let app = AppLauncher.launch(.empty)
        openSyncSettings(app)
        app.buttons["sync.recovered"].tap()
        XCTAssertTrue(app.staticTexts["Nothing Recovered"].waitForExistence(timeout: 5))
    }

    @MainActor func testLibraryShowsSyncStatusIndicator() {
        let app = AppLauncher.launch(.libraryBasic)
        XCTAssertTrue(app.buttons["library.syncStatus"].waitForExistence(timeout: 5))
    }
}
