import CoreGraphics
import PDFKit
import Testing
import SheafnoteCore
@testable import Sheafnote

@MainActor
@Suite("PDF backgrounds and export")
struct BackgroundAndExportTests {
    @Test func registersTheBackgroundLayerAndTheEditorEntries() throws {
        let fx = try PdfIOFixture()
        let snapshot = PageSnapshot(pageID: UUID(), notebookID: UUID(), size: CGSize(width: 100, height: 100),
                                    backgroundAssetID: UUID(), backgroundPageIndex: 0, template: .blank, paperColor: .white)
        #expect(fx.host.layers.providers(for: snapshot).contains { $0.slot == .background })
        let plain = PageSnapshot(pageID: UUID(), notebookID: UUID(), size: .zero, backgroundAssetID: nil, backgroundPageIndex: nil,
                                 template: .blank, paperColor: .white)
        #expect(!fx.host.layers.providers(for: plain).contains { $0.slot == .background })
        #expect(fx.host.notebookMenu.barItems.contains { $0.id == "pdfio.export" })
        #expect(fx.host.notebookMenu.pageMenuItems.contains { $0.id == "pdfio.exportPages" })
        #expect(fx.host.notebookMenu.menuItems.contains { $0.id == "pdfio.insert" && $0.group == .insert })
        #expect(fx.host.library.importHandlers.map(\.id).sorted() == ["pdfio.archive", "pdfio.images", "pdfio.pdf"])
        #expect(fx.host.library.notebookActions.contains { $0.id == "pdfio.export" })
        #expect(fx.host.settings.sections.contains { $0.id == "pdfio.backup" && $0.order == 30 })
        #expect(fx.host.library.backgroundTasks.contains { $0.id == "pdfio.backup" })
    }

    @Test func importHandlerRoutingFindsTheRightHandlerPerExtension() throws {
        let fx = try PdfIOFixture()
        #expect(fx.host.library.importHandler(for: URL(filePath: "/tmp/a.pdf"))?.id == "pdfio.pdf")
        #expect(fx.host.library.importHandler(for: URL(filePath: "/tmp/a.png"))?.id == "pdfio.images")
        #expect(fx.host.library.importHandler(for: URL(filePath: "/tmp/a.heic"))?.id == "pdfio.images")
        #expect(fx.host.library.importHandler(for: URL(filePath: "/tmp/a.sheafnote"))?.id == "pdfio.archive")
        #expect(fx.host.library.importHandler(for: URL(filePath: "/tmp/a.docx")) == nil)
    }

    @Test func cacheSharesOneDecodedDocumentAcrossPages() async throws {
        let fx = try PdfIOFixture()
        let result = try await fx.importer.importPDF(PdfIOFixture.pdf(pages: 3), title: "T", into: nil)
        let page = try #require(fx.services.pages.page(id: result.pageIDs[0]))
        let assetID = try #require(page.backgroundAssetID)
        let cache = BackgroundAssetCache(pages: fx.services.pages)
        guard case .pdf(let first) = try await cache.asset(assetID), case .pdf(let second) = try await cache.asset(assetID) else {
            Issue.record("expected a PDF background"); return
        }
        #expect(first === second && first.pageCount == 3)
    }

    @Test func backgroundLayerDrawsThePdfPageUprightIntoAnExportContext() async throws {
        let fx = try PdfIOFixture()
        let result = try await fx.importer.importPDF(PdfIOFixture.pdf(pages: 2), title: "T", into: nil)
        let image = try await fx.services.pageRenderer.renderImage(pageID: result.pageIDs[1], rect: nil, scale: 1, options: .export)
        #expect(image.width == 612 && image.height == 792)
        #expect(PdfIOFixture.luma(of: image, x: 300, y: 10) < 60, "the PDF's black bar is at the top")
        #expect(PdfIOFixture.luma(of: image, x: 300, y: 400) > 230, "the rest stays paper white")
    }

    @Test func excludingBackgroundsLeavesOnlyPaperAndInk() async throws {
        let fx = try PdfIOFixture()
        let result = try await fx.importer.importPDF(PdfIOFixture.pdf(pages: 1), title: "T", into: nil)
        var options = RenderOptions.export
        options.includeBackground = false
        let image = try await fx.services.pageRenderer.renderImage(pageID: result.pageIDs[0], rect: nil, scale: 1, options: options)
        #expect(PdfIOFixture.luma(of: image, x: 300, y: 10) > 230)
    }

    @Test func imagePagesRenderTheirPicture() async throws {
        let fx = try PdfIOFixture()
        let png = UIImage.solid(.red, size: CGSize(width: 80, height: 40)).pngData()!
        let result = try await fx.importer.importImages([ImportedImage(data: png, filename: "r.png")], title: "Pics", into: nil)
        let image = try await fx.services.pageRenderer.renderImage(pageID: result.pageIDs[0], rect: nil, scale: 0.5, options: .export)
        let notebook = try #require(fx.services.library.notebook(id: result.notebookID))
        #expect(notebook.title == "Pics")
        #expect(PdfIOFixture.luma(of: image, x: image.width / 2, y: image.height / 2) < 150)
    }

    @Test func pdfExportProducesOnePagePerNotebookPageWithTheBackground() async throws {
        let fx = try PdfIOFixture()
        let result = try await fx.importer.importPDF(PdfIOFixture.pdf(pages: 4), title: "Slides", into: nil)
        let notebook = try #require(fx.services.library.notebook(id: result.notebookID))
        let request = ExportRequest(notebooks: [notebook], scope: .wholeNotebook, kind: .pdf, includeBackground: true, imageScale: 2)
        var fractions: [Double] = []
        let output = try await ExportRunner(services: fx.services).run(request) { fractions.append($0) }
        defer { try? FileManager.default.removeItem(at: output.directory) }
        #expect(output.files.map(\.lastPathComponent) == ["Slides.pdf"] && output.pageCount == 4)
        let doc = try #require(PDFDocument(url: output.files[0]))
        #expect(doc.pageCount == 4)
        #expect(fractions.last == 1)
        let thumb = try #require(doc.page(at: 0)).thumbnail(of: CGSize(width: 306, height: 396), for: .mediaBox).cgImage
        #expect(PdfIOFixture.luma(of: try #require(thumb), x: 150, y: 8) < 80)
    }

    @Test func exportOfSelectedPagesKeepsNotebookOrderAndSizes() async throws {
        let fx = try PdfIOFixture()
        let result = try await fx.importer.importPDF(PdfIOFixture.pdf(pages: 5), title: "Five", into: nil)
        let notebook = try #require(fx.services.library.notebook(id: result.notebookID))
        let chosen: Set<UUID> = [result.pageIDs[3], result.pageIDs[1]]
        let request = ExportRequest(notebooks: [notebook], scope: .pages(chosen), kind: .pdf, includeBackground: false, imageScale: 2)
        let output = try await ExportRunner(services: fx.services).run(request) { _ in }
        defer { try? FileManager.default.removeItem(at: output.directory) }
        #expect(try #require(PDFDocument(url: output.files[0])).pageCount == 2)
    }

    @Test func imageExportNamesFilesByPageNumberAndHonorsRanges() async throws {
        let fx = try PdfIOFixture()
        let result = try await fx.importer.importPDF(PdfIOFixture.pdf(pages: 12), title: "Bio", into: nil)
        let notebook = try #require(fx.services.library.notebook(id: result.notebookID))
        let request = ExportRequest(notebooks: [notebook], scope: .numbers([2, 11]), kind: .png, includeBackground: true, imageScale: 1)
        let output = try await ExportRunner(services: fx.services).run(request) { _ in }
        defer { try? FileManager.default.removeItem(at: output.directory) }
        #expect(output.files.map(\.lastPathComponent) == ["Bio-p02.png", "Bio-p11.png"])
        let data = try Data(contentsOf: output.files[0])
        #expect(UIImage(data: data)?.size == CGSize(width: 612, height: 792))
    }

    @Test func archiveExportRoundTripsThroughTheImporter() async throws {
        let fx = try PdfIOFixture()
        let result = try await fx.importer.importPDF(PdfIOFixture.pdf(pages: 2), title: "Keep", into: nil)
        let notebook = try #require(fx.services.library.notebook(id: result.notebookID))
        let request = ExportRequest(notebooks: [notebook], scope: .wholeNotebook, kind: .archive, includeBackground: true, imageScale: 1)
        let output = try await ExportRunner(services: fx.services).run(request) { _ in }
        defer { try? FileManager.default.removeItem(at: output.directory) }
        #expect(output.files[0].pathExtension == "sheafnote")

        let target = try PdfIOFixture()
        let summary = try await ArchiveRestore.run(url: output.files[0], folderID: nil, services: target.services)
        #expect(summary.notebookIDs.count == 1 && summary.pageCount == 2)
        let copy = try #require(target.services.library.notebook(id: summary.notebookIDs[0]))
        #expect(copy.title == "Keep" && copy.folderID == nil)
        let image = try await target.services.pageRenderer.renderImage(pageID: try #require(target.services.pages.orderedPages(of: copy.id).first).id,
                                                                       rect: nil, scale: 1, options: .export)
        #expect(PdfIOFixture.luma(of: image, x: 300, y: 10) < 60, "the PDF background survived the round trip")
    }

    @Test func textDocumentsCanOnlyBeExportedAsBackups() async throws {
        let fx = try PdfIOFixture()
        let doc = try fx.services.library.createNotebook(title: "Essay", kind: .text, cover: .default, template: .blank,
                                                         paperSize: .a4, orientation: .portrait, paperColor: .white, in: nil)
        let model = ExportModel(services: fx.services, notebooks: [doc])
        #expect(model.availableKinds == [.archive] && model.kind == .archive)
        let request = ExportRequest(notebooks: [doc], scope: .wholeNotebook, kind: .pdf, includeBackground: true, imageScale: 1)
        await #expect(throws: PdfIOAppError.self) { try await ExportRunner(services: fx.services).run(request) { _ in } }
    }

    @Test func exportModelValidatesTheTypedRange() async throws {
        let fx = try PdfIOFixture()
        let result = try await fx.importer.importPDF(PdfIOFixture.pdf(pages: 6), title: "R", into: nil)
        let notebook = try #require(fx.services.library.notebook(id: result.notebookID))
        let model = ExportModel(services: fx.services, notebooks: [notebook], currentPageID: result.pageIDs[0])
        #expect(model.pageCount == 6 && model.availablePageChoices == [.whole, .current, .range])
        model.pageChoice = .range
        #expect(!model.canStart)
        model.rangeText = "2-4"
        #expect(model.canStart && model.scope == .numbers([2, 3, 4]))
        model.rangeText = "9"
        #expect(!model.canStart)
        model.kind = .archive
        #expect(model.canStart && model.scope == .wholeNotebook)
    }

    @Test func staleExportFoldersAreSweptButFreshOnesStay() throws {
        let fm = FileManager.default
        let sandbox = try PdfIOFixture.temporaryFolder()
        defer { try? fm.removeItem(at: sandbox) }
        let old = sandbox.appending(path: "\(ExportFolder.prefix)old")
        let fresh = sandbox.appending(path: "\(ExportFolder.prefix)fresh")
        let unrelated = sandbox.appending(path: "somebody-elses-folder")
        for url in [old, fresh, unrelated] { try fm.createDirectory(at: url, withIntermediateDirectories: true) }
        try fm.setAttributes([.modificationDate: Date().addingTimeInterval(-7200)], ofItemAtPath: old.path)
        try fm.setAttributes([.modificationDate: Date().addingTimeInterval(-7200)], ofItemAtPath: unrelated.path)
        ExportFolder.removeStale(in: sandbox, olderThan: 3600)
        #expect(!fm.fileExists(atPath: old.path))
        #expect(fm.fileExists(atPath: fresh.path) && fm.fileExists(atPath: unrelated.path))
    }
}

private extension UIImage {
    static func solid(_ color: UIColor, size: CGSize) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { ctx in
            color.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }
}
