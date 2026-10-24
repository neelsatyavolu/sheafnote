import XCTest

enum UITestScenario: String {
    case empty, libraryBasic, notebookWith3Pages, pdfNotebook, recorded
}

enum AppLauncher {
    @MainActor
    static func launch(_ scenario: UITestScenario = .empty) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestMode", "1", "-UITestScenario", scenario.rawValue, "-AppleLanguages", "(en)"]
        app.launch()
        return app
    }
}
