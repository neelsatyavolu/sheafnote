import XCTest

/// Laser, zoom window and presenting. An external display cannot be attached in the simulator, so the external scene is
/// covered by unit tests of the state machine; here the on-device presenter stands in.
final class PresentUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    @MainActor private func openNotebook() -> XCUIApplication {
        let app = AppLauncher.launch(.notebookWith3Pages)
        let notebook = app.buttons["item.Three Pages"]
        XCTAssertTrue(notebook.waitForExistence(timeout: 10))
        notebook.tap()
        XCTAssertTrue(app.descendants(matching: .any)["editor.page.1"].waitForExistence(timeout: 10))
        return app
    }

    @MainActor private func chooseFromMoreTools(_ name: String, in app: XCUIApplication) {
        app.buttons["editor.tool.more"].tap()
        let item = app.buttons[name]
        XCTAssertTrue(item.waitForExistence(timeout: 5), "\(name) should be in the More tools menu")
        item.tap()
    }

    @MainActor func testLaserToolIsSelectableAndShowsItsOptions() {
        let app = openNotebook()
        let laser = app.buttons["editor.tool.laser"]
        XCTAssertTrue(laser.waitForExistence(timeout: 5))
        laser.tap()
        XCTAssertTrue(laser.isSelected)
        XCTAssertTrue(app.buttons["present.laser.color.green"].waitForExistence(timeout: 5))
        app.buttons["present.laser.color.green"].tap()
        let selected = NSPredicate(format: "value == %@", "Selected")
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: selected, object: app.buttons["present.laser.color.green"])],
                                        timeout: 5), .completed, "the tapped colour should become selected")
    }

    @MainActor func testLaserDragDoesNotWriteInk() {
        let app = openNotebook()
        app.buttons["editor.tool.laser"].tap()
        let page = app.descendants(matching: .any)["editor.page.1"]
        page.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.3))
            .press(forDuration: 0.05, thenDragTo: page.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.4)))
        XCTAssertTrue(((page.value as? String) ?? "").contains("0 strokes"), "the laser must never write ink")
    }

    @MainActor func testZoomWindowStripAppearsAndWritesToThePage() {
        let app = openNotebook()
        chooseFromMoreTools("Zoom Window", in: app)
        let strip = app.descendants(matching: .any)["present.zoom.strip"]
        XCTAssertTrue(strip.waitForExistence(timeout: 5), "the zoom strip should float over the notebook")

        strip.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: strip.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.5)))

        let page = app.descendants(matching: .any)["editor.page.1"]
        let predicate = NSPredicate(format: "value CONTAINS %@", "1 stroke")
        let result = XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: page)], timeout: 8)
        XCTAssertEqual(result, .completed, "writing in the strip should add a stroke to the page, got \(String(describing: page.value))")
    }

    @MainActor func testZoomWindowCloseHidesTheStrip() {
        let app = openNotebook()
        chooseFromMoreTools("Zoom Window", in: app)
        XCTAssertTrue(app.descendants(matching: .any)["present.zoom.strip"].waitForExistence(timeout: 5))
        app.buttons["present.zoom.close"].tap()
        let gone = NSPredicate(format: "exists == false")
        let strip = app.descendants(matching: .any)["present.zoom.strip"]
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: gone, object: strip)], timeout: 5), .completed)
    }

    @MainActor func testPresentOnDeviceShowsTheCleanPageAndCanStop() {
        let app = openNotebook()
        app.buttons["editor.more"].tap()
        let present = app.buttons["editor.menu.present"]
        XCTAssertTrue(present.waitForExistence(timeout: 5), "Present should be in the more menu")
        present.tap()

        XCTAssertTrue(app.switches["present.option.laser"].waitForExistence(timeout: 5))
        app.buttons["present.start"].tap()

        let close = app.buttons["present.presenter.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 8), "with no display the page fills this screen")
        XCTAssertFalse(app.buttons["editor.undo"].isHittable, "toolbars are hidden while presenting")
        close.tap()
        let gone = NSPredicate(format: "exists == false")
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: gone, object: close)], timeout: 8), .completed)
        XCTAssertTrue(app.buttons["editor.undo"].waitForExistence(timeout: 5))
    }
}
