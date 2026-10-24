import XCTest

/// Audio and flashcards. The microphone and speaker are scripted (`-UITestMode 1`), so no permission prompt appears.
final class AudioStudyUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    @MainActor private func openNotebook(micDenied: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestMode", "1", "-UITestScenario", UITestScenario.notebookWith3Pages.rawValue,
                               "-AppleLanguages", "(en)"]
        if micDenied { app.launchArguments += ["-UITestMicDenied", "1"] }
        app.launch()
        let notebook = app.buttons["item.Three Pages"]
        XCTAssertTrue(notebook.waitForExistence(timeout: 10))
        notebook.tap()
        XCTAssertTrue(app.descendants(matching: .any)["editor.page.1"].waitForExistence(timeout: 10))
        return app
    }

    @MainActor private func openAudioSheet(_ app: XCUIApplication) {
        app.buttons["editor.more"].tap()
        let item = app.buttons["editor.menu.audio.record"]
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        item.tap()
        XCTAssertTrue(app.buttons["audio.record"].waitForExistence(timeout: 5))
    }

    @MainActor func testRecordStopAndPlayBack() {
        let app = openNotebook()
        openAudioSheet(app)
        XCTAssertTrue(app.staticTexts["audio.empty"].exists || app.descendants(matching: .any)["audio.empty"].exists)
        app.buttons["audio.record"].tap()
        sleep(2)
        app.buttons["audio.record"].tap()
        let row = app.buttons["audio.row.Recording 1"]
        XCTAssertTrue(row.waitForExistence(timeout: 8), "the saved recording should be listed")
        row.tap()
        XCTAssertTrue(app.buttons["audio.player.playPause"].waitForExistence(timeout: 8), "playback bar should appear")
        XCTAssertTrue(app.descendants(matching: .any)["audio.overlay"].waitForExistence(timeout: 5), "playback overlay")
        app.buttons["audio.player.playPause"].tap()
        XCTAssertEqual(app.buttons["audio.player.playPause"].label, "Play")
        app.buttons["audio.player.close"].tap()
        XCTAssertFalse(app.buttons["audio.player.playPause"].waitForExistence(timeout: 2))
    }

    @MainActor func testDeniedMicrophoneShowsExplanation() {
        let app = openNotebook(micDenied: true)
        openAudioSheet(app)
        app.buttons["audio.record"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["audio.denied"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["audio.openSettings"].exists)
    }

    @MainActor func testMakeFlashcardFromPageThenReviewIt() {
        let app = openNotebook()
        app.buttons["editor.pages"].tap()
        let thumb = app.descendants(matching: .any)["editor.thumb.1"]
        XCTAssertTrue(thumb.waitForExistence(timeout: 8))
        thumb.press(forDuration: 1.2)
        let make = app.buttons["Make flashcards"]
        XCTAssertTrue(make.waitForExistence(timeout: 5))
        make.tap()
        let save = app.buttons["flashcard.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 8))
        let enabled = NSPredicate(format: "isEnabled == true")
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: enabled, object: save)], timeout: 10), .completed)
        save.tap()
        XCTAssertFalse(save.waitForExistence(timeout: 3), "sheet closes after the card is added")

        app.buttons["editor.pages"].tap()
        let tabs = app.segmentedControls["editor.navigator.tabs"]
        XCTAssertTrue(tabs.waitForExistence(timeout: 8))
        tabs.buttons["Flashcards"].tap()
        XCTAssertTrue(app.buttons["flashcards.studyAll"].waitForExistence(timeout: 5))
        app.staticTexts["General"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["General"].waitForExistence(timeout: 5), "deck opens its card list")
        app.navigationBars["General"].buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["flashcards.studyAll"].waitForExistence(timeout: 5))
        app.buttons["flashcards.studyAll"].tap()
        XCTAssertTrue(app.buttons["study.reveal"].waitForExistence(timeout: 5))
        app.buttons["study.reveal"].tap()
        XCTAssertTrue(app.buttons["study.grade.good"].waitForExistence(timeout: 3))
        app.buttons["study.grade.good"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["study.finished"].waitForExistence(timeout: 5))
    }
}
