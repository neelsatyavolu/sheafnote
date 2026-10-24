import XCTest

/// Reaching controls that sit in different places on iPad and iPhone.
/// iPad: library sections are in the sidebar, Settings is in the sidebar's bottom bar, and editor bar items are in the
/// top bar. iPhone: sections and Settings are in the "Library" menu, and editor bar items are in the "more" menu.
/// The app uses the same accessibility identifiers in both places.
extension XCUIApplication {
    /// Taps a library section ("sidebar.search", "sidebar.favorites", …) or "library.settings".
    @MainActor func openLibrarySection(_ identifier: String, file: StaticString = #filePath, line: UInt = #line) {
        let sectionMenu = buttons["library.sectionMenu"]
        if sectionMenu.waitForExistence(timeout: 3) {
            sectionMenu.tap()
        }
        // iPhone menu rows and the iPad Settings button are buttons; iPad sidebar rows are labels (text plus an icon
        // that is not hittable, so never match "any").
        let button = buttons[identifier], text = staticTexts[identifier]
        let deadline = Date().addingTimeInterval(5)
        while !button.exists, !text.exists, Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.2)) }
        XCTAssertTrue(button.exists || text.exists, "\(identifier) should be reachable", file: file, line: line)
        (button.exists ? button : text).tap()
    }

    /// An editor bar button ("editor.export", "search.bookmark", …), opening the "more" menu first on iPhone.
    @MainActor func editorBarButton(_ identifier: String, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let inBar = buttons[identifier]
        if inBar.waitForExistence(timeout: 2), inBar.isHittable { return inBar }
        let more = buttons["editor.more"]
        XCTAssertTrue(more.waitForExistence(timeout: 5), "editor more menu", file: file, line: line)
        more.tap()
        let inMenu = buttons[identifier]
        XCTAssertTrue(inMenu.waitForExistence(timeout: 5), "\(identifier) should be in the more menu", file: file, line: line)
        return inMenu
    }
}
