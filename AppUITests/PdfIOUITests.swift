import UIKit
import XCTest

final class PdfIOUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    // MARK: Helpers

    /// A PDF with `pages` pages written where the app (running in the simulator on the same Mac) can read it.
    private func makeFixturePDF(pages: Int) throws -> URL {
        let url = URL(fileURLWithPath: "/tmp/sheafnote-uitest-\(UUID().uuidString).pdf")
        let size = CGSize(width: 612, height: 792)
        let data = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: size)).pdfData { ctx in
            for i in 1...pages {
                ctx.beginPage()
                ("Fixture page \(i)" as NSString).draw(at: CGPoint(x: 72, y: 72), withAttributes: [.font: UIFont.systemFont(ofSize: 32)])
            }
        }
        try data.write(to: url)
        return url
    }

    @MainActor private func launch(importing pdf: URL? = nil, scenario: UITestScenario = .empty) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestMode", "1", "-UITestScenario", scenario.rawValue, "-AppleLanguages", "(en)"]
        if let pdf { app.launchArguments += ["-PdfIOImportFixture", pdf.path] }
        app.launch()
        return app
    }

    @MainActor private func openNotebook(_ title: String, in app: XCUIApplication) {
        let notebook = app.buttons["item.\(title)"]
        XCTAssertTrue(notebook.waitForExistence(timeout: 15), "\(title) should be in the library")
        notebook.tap()
        XCTAssertTrue(app.buttons["editor.pageIndicator"].waitForExistence(timeout: 15), "the editor should open")
    }

    @MainActor private func runPDFExport(in app: XCUIApplication) -> XCUIElement {
        let export = app.buttons["editor.export"]
        XCTAssertTrue(export.waitForExistence(timeout: 10), "the editor bar has an Export button")
        export.tap()
        let start = app.buttons["export.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        start.tap()
        let pageCount = app.descendants(matching: .any)["export.pageCount"]
        XCTAssertTrue(pageCount.waitForExistence(timeout: 60), "the export should finish")
        return pageCount
    }

    // MARK: Tests

    @MainActor func testExportsTheOpenNotebookAsAPdfWithEveryPage() {
        let app = launch(scenario: .notebookWith3Pages)
        openNotebook("Three Pages", in: app)
        let pageCount = runPDFExport(in: app)
        XCTAssertTrue(pageCount.label.contains("3"), "all 3 pages are exported, got: \(pageCount.label)")
        XCTAssertTrue(app.descendants(matching: .any)["export.result"].exists)
        XCTAssertTrue(app.buttons["export.share"].exists, "the exported file can be shared or saved")
    }

    @MainActor func testImportsAPdfFromAFileThenExportsItWithAllPages() throws {
        let pdf = try makeFixturePDF(pages: 5)
        defer { try? FileManager.default.removeItem(at: pdf) }
        let app = launch(importing: pdf)
        openNotebook("Imported Fixture", in: app)
        XCTAssertEqual(app.buttons["editor.pageIndicator"].label, "Page 1 of 5")
        let pageCount = runPDFExport(in: app)
        XCTAssertTrue(pageCount.label.contains("5"), "got: \(pageCount.label)")
    }

    @MainActor func testExportSheetOffersFormatsAndPageRange() {
        let app = launch(scenario: .notebookWith3Pages)
        openNotebook("Three Pages", in: app)
        app.buttons["editor.export"].tap()
        XCTAssertTrue(app.buttons["export.format"].waitForExistence(timeout: 10))
        app.buttons["export.pages"].tap()
        app.buttons["Page range"].tap()
        let range = app.textFields["export.range"]
        XCTAssertTrue(range.waitForExistence(timeout: 5))
        range.tap()
        range.typeText("9")
        XCTAssertFalse(app.buttons["export.start"].isEnabled, "page 9 doesn't exist in a 3-page notebook")
    }

    @MainActor func testSettingsHasImportAndBackupSection() {
        let app = launch()
        let settings = app.buttons["library.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()
        let row = app.buttons["settings.pdfio.backup"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(app.buttons["backup.folder"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["backup.now"].isEnabled, "no folder chosen yet")
        XCTAssertTrue(app.buttons["backup.exportLibrary"].exists && app.buttons["backup.import"].exists)
    }
}
