import XCTest

/// Not a test: captures the screenshots for the Sheafnote showcase page. Skipped unless the ink file is given:
///   uv run --with Hershey-Fonts python -I scripts/showcase/make_ink.py            (writes showcase-ink.json)
///   TEST_RUNNER_SHEAFNOTE_SHOWCASE_INK=$PWD/showcase-ink.json xcodebuild test \
///     -only-testing:SheafnoteUITests/ShowcaseScreens ...
/// Screens are attached to the result bundle with names like "showcase-ipad-editor".
final class ShowcaseScreens: XCTestCase {
    private var inkPath: String? { ProcessInfo.processInfo.environment["SHEAFNOTE_SHOWCASE_INK"] }
    @MainActor private var device: String { UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone" }

    override func setUp() { continueAfterFailure = true }

    @MainActor func testCaptureShowcase() throws {
        guard let ink = inkPath else { throw XCTSkip("set TEST_RUNNER_SHEAFNOTE_SHOWCASE_INK to capture screenshots") }
        if device == "ipad" { XCUIDevice.shared.orientation = .landscapeLeft }
        let app = XCUIApplication()
        app.launchArguments = ["-UITestMode", "1", "-UITestScenario", "showcase", "-UITestShowcaseInk", ink,
                               "-AppleLanguages", "(en)"]
        app.launch()

        let biology = app.buttons["item.Biology 201"]
        XCTAssertTrue(biology.waitForExistence(timeout: 15))
        snap(app, "library")

        // Portrait shows the whole page; landscape zooms to the page width.
        if device == "ipad" { XCUIDevice.shared.orientation = .portrait }
        biology.tap()
        XCTAssertTrue(app.buttons["editor.pageIndicator"].waitForExistence(timeout: 10))
        sleep(6)   // let PencilKit finish drawing the page at full resolution
        snap(app, "editor")
        guard device == "ipad" else { return }

        app.buttons["editor.pages"].tap()
        sleep(2)
        snap(app, "pages")
        let tabs = app.segmentedControls["editor.navigator.tabs"]
        if tabs.waitForExistence(timeout: 5) {
            tabs.buttons["Flashcards"].tap()
            let study = app.buttons["flashcards.studyAll"]
            if study.waitForExistence(timeout: 5) {
                study.tap()
                sleep(1)
                snap(app, "study-front")
                if app.buttons["study.reveal"].waitForExistence(timeout: 3) {
                    app.buttons["study.reveal"].tap()
                    sleep(1)
                    snap(app, "study-back")
                }
                app.buttons["study.close"].tap()
            }
        }
        if app.buttons["Done"].exists { app.buttons["Done"].tap() }
        app.buttons["editor.back"].tap()
        XCUIDevice.shared.orientation = .landscapeLeft

        // Handwriting is searchable once the recognizer has read the pages.
        app.openLibrarySection("sidebar.search")
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("mitochondria")
        _ = app.descendants(matching: .any)["search.result.page.Biology 201.1"].waitForExistence(timeout: 45)
        if app.keyboards.count > 0 { app.typeText("\n") }
        sleep(1)
        snap(app, "search")

        app.openLibrarySection("sidebar.documents")
        app.buttons["library.newMenu"].tap()
        app.buttons["library.new.notebook"].tap()
        sleep(2)
        snap(app, "new-notebook")
    }

    @MainActor private func snap(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "showcase-\(device)-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
