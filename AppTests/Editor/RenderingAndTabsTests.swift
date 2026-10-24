import CoreGraphics
import PencilKit
import Testing
import UIKit
import SheafnoteCore
@testable import Sheafnote

/// Counts pixels that are clearly not paper white.
private func inkPixels(in image: CGImage) -> Int {
    let w = image.width, h = image.height
    var data = [UInt8](repeating: 255, count: w * h * 4)
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
          let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: space,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return -1 }
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    var count = 0
    for i in stride(from: 0, to: data.count, by: 4) where data[i] < 120 && data[i + 1] < 120 && data[i + 2] < 120 { count += 1 }
    return count
}

@MainActor
@Suite struct RenderingAndTabsTests {
    @Test func renderImageIsPageSizedAndShowsInk() async throws {
        let f = try EditorFixture()
        let page = try f.page()
        let blank = try await f.services.pageRenderer.renderImage(pageID: page.pageID, rect: nil, scale: 1, options: .screen)
        #expect(blank.width == 595 && blank.height == 842)
        #expect(inkPixels(in: blank) == 0)

        page.setDrawing(PKDrawingFactory.one(), undoName: "Draw")
        page.flush()
        let inked = try await f.services.pageRenderer.renderImage(pageID: page.pageID, rect: nil, scale: 1, options: .screen)
        #expect(inkPixels(in: inked) > 200)
        var noInk = RenderOptions.screen
        noInk.includeInk = false
        let without = try await f.services.pageRenderer.renderImage(pageID: page.pageID, rect: nil, scale: 1, options: noInk)
        #expect(inkPixels(in: without) == 0)
    }

    @Test func inkLandsWhereItWasDrawn() async throws {
        let f = try EditorFixture()
        let page = try f.page()
        page.setDrawing(PKDrawing(strokes: [TestInk.stroke(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 200, y: 100), width: 8)]),
                        undoName: "Draw")
        page.flush()
        let crop = CGRect(x: 90, y: 90, width: 120, height: 30)
        let top = try await f.services.pageRenderer.renderImage(pageID: page.pageID, rect: crop, scale: 2, options: .screen)
        #expect(top.width == 240 && top.height == 60)
        #expect(inkPixels(in: top) > 100)
        let elsewhere = try await f.services.pageRenderer.renderImage(pageID: page.pageID, rect: CGRect(x: 90, y: 600, width: 120, height: 30),
                                                                      scale: 2, options: .screen)
        #expect(inkPixels(in: elsewhere) == 0)
    }

    @Test func templateIsDrawnUnlessBackgroundsAreOff() async throws {
        let f = try EditorFixture(template: .gridSmall)
        let id = f.firstPageID
        let with = try await f.services.pageRenderer.renderImage(pageID: id, rect: nil, scale: 1, options: .screen)
        var plain = RenderOptions.screen
        plain.includeBackground = false
        let without = try await f.services.pageRenderer.renderImage(pageID: id, rect: nil, scale: 1, options: plain)
        #expect(with.dataProvider?.data as Data? != without.dataProvider?.data as Data?)
    }

    @Test func pdfPageIsDrawnIntoTheMediaBox() async throws {
        let f = try EditorFixture(template: .ruledCollege)
        let page = try f.page()
        page.setDrawing(PKDrawingFactory.one(), undoName: "Draw")
        page.flush()
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 595, height: 842)
        let consumer = try #require(CGDataConsumer(data: data))
        let ctx = try #require(CGContext(consumer: consumer, mediaBox: &box, nil))
        ctx.beginPDFPage(nil)
        try await f.services.pageRenderer.renderPDFPage(pageID: page.pageID, into: ctx, mediaBox: box, options: .export)
        ctx.endPDFPage()
        ctx.closePDF()
        let document = try #require(CGPDFDocument(CGDataProvider(data: data as CFData)!))
        #expect(document.numberOfPages == 1)
    }

    @Test func thumbnailsAreCachedAndInvalidatedByChanges() async throws {
        let f = try EditorFixture()
        let page = try f.page()
        let first = try #require(await f.services.pageRenderer.thumbnail(pageID: page.pageID, width: 200))
        #expect(first.width == 200)
        let again = try #require(await f.services.pageRenderer.thumbnail(pageID: page.pageID, width: 200))
        #expect(again === first)   // served from the cache

        page.setDrawing(PKDrawingFactory.one(), undoName: "Draw")
        page.flush()
        let changed = try #require(await f.services.pageRenderer.thumbnail(pageID: page.pageID, width: 200))
        #expect(changed !== first)
        #expect(inkPixels(in: changed) > inkPixels(in: first))
        #expect(await f.services.pageRenderer.thumbnail(pageID: UUID(), width: 200) == nil)
    }

    @Test func thumbnailCacheSurvivesRelaunchThroughDisk() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("thumbs-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let image = try #require(TemplateRenderer.renderImage(.blank, size: CGSize(width: 20, height: 30), paper: .white))
        ThumbnailCache(directory: dir).store(image, for: "k")
        let reopened = ThumbnailCache(directory: dir).image(for: "k")
        #expect(reopened?.width == 20 && reopened?.height == 30)
        #expect(ThumbnailCache(directory: dir).image(for: "missing") == nil)
    }

    @Test func rendererIsRegisteredIntoServices() throws {
        let f = try EditorFixture()
        #expect(f.services.pageRenderer is EditorPageRenderer)
    }

    @Test func unsupportedElementsAreKeptAndDrawnAsPlaceholders() throws {
        let f = try EditorFixture()
        let page = try f.page()
        let element = ElementValue(id: UUID(), pageID: page.pageID, kind: .link, frame: CGRect(x: 0, y: 0, width: 40, height: 40),
                                   rotation: 0, zIndex: 0, payload: Data(), assetID: nil)
        try page.elements.add(element, undoName: "Add")
        #expect(f.host.elementRenderers.renderer(for: .link) == nil)
        #expect(page.elementValues.count == 1)   // no renderer registered, still stored and listed
        #expect(try f.services.pages.elements(on: page.pageID).count == 1)
        let layer = ElementLayerProvider(slot: .belowInk, host: f.host).makeLayerView(for: page)
        #expect(layer is ElementLayerView)
    }

    // MARK: Layers

    @Test func layerStackOrder() throws {
        let f = try EditorFixture(template: .gridSmall)
        let page = try f.page()
        let slots = f.host.layers.providers(for: page.snapshot).map(\.slot)
        #expect(slots == [.paper, .template, .belowInk, .ink, .aboveInk])
        let blank = try EditorFixture(template: .blank)
        let blankPage = try blank.page()
        #expect(blank.host.layers.providers(for: blankPage.snapshot).map(\.slot) == [.paper, .belowInk, .ink, .aboveInk])
    }

    @Test func containerStacksLayersUnderTheOverlays() throws {
        let f = try EditorFixture(template: .ruledNarrow)
        let page = try f.page()
        let container = PageContainerView(page: page, session: f.session, number: 1, count: 1)
        #expect(container.bounds.size == page.pageSize)
        #expect(container.subviews.last is SelectionOverlayView)
        #expect(container.subviews.contains { $0 is InkCanvasView })
        let canvasIndex = try #require(container.subviews.firstIndex { $0 is InkCanvasView })
        let templateIndex = try #require(container.subviews.firstIndex { $0 is TemplateTiledView })
        #expect(templateIndex < canvasIndex)
        #expect(page.canvas?.accessibilityIdentifier == "editor.page.1")
    }

    @Test func toolConfiguratorPointsCanvasAtThePenOrDisablesItForOverlayTools() throws {
        let f = try EditorFixture()
        let page = try f.page()
        let container = PageContainerView(page: page, session: f.session, number: 1, count: 1)
        let canvas = try #require(page.canvas)
        ToolConfigurator.apply(f.session.toolConfiguration, session: f.session, container: container)
        #expect((canvas.tool as? PKInkingTool)?.inkType == .pen && canvas.isUserInteractionEnabled)

        f.session.prefs.values.eraserHighlighterOnly = true
        f.session.toolState.select(.eraser)
        ToolConfigurator.apply(f.session.toolConfiguration, session: f.session, container: container)
        #expect(!canvas.isUserInteractionEnabled && container.markerEraser.isEnabled)

        f.session.prefs.values.eraserHighlighterOnly = false
        ToolConfigurator.apply(f.session.toolConfiguration, session: f.session, container: container)
        #expect(canvas.isUserInteractionEnabled && (canvas.tool as? PKEraserTool)?.eraserType == .vector)

        f.session.prefs.inputMode = .pencilOnly
        f.session.toolState.inputMode = .pencilOnly
        ToolConfigurator.apply(f.session.toolConfiguration, session: f.session, container: container)
        #expect(canvas.drawingPolicy == .pencilOnly)
    }

    // MARK: Tabs

    @Test func tabsKeepSessionsAndPickNeighboursOnClose() throws {
        let f = try EditorFixture()
        let other = try f.services.library.createNotebook(title: "Other", kind: .paged, cover: .default, template: .blank,
                                                          paperSize: .a4, orientation: .portrait, paperColor: .white, in: nil)
        let tabs = EditorTabs()
        let s1 = tabs.session(for: f.notebook, host: f.host, sizing: .fixed(.zero))
        #expect(tabs.session(for: f.notebook, host: f.host, sizing: .fixed(.zero)) === s1)
        tabs.open(f.notebook)
        tabs.open(other)
        #expect(tabs.openIDs == [f.notebook.id, other.id] && tabs.activeID == other.id)
        tabs.close(id: other.id)
        #expect(tabs.activeID == f.notebook.id)
        tabs.closeAll()
        #expect(tabs.openIDs.isEmpty && tabs.activeID == nil)
    }

    @Test func aNotebookIsLiveInOneWindowAtATime() {
        let tabs = EditorTabs()
        let notebook = UUID(), first = UUID(), second = UUID()
        #expect(tabs.claim(notebook, token: first))
        #expect(tabs.claim(notebook, token: first))      // the owner may re-claim
        #expect(!tabs.claim(notebook, token: second))    // a second window is refused
        tabs.release(notebook, token: second)            // a non-owner cannot release it
        #expect(!tabs.claim(notebook, token: second))
        tabs.release(notebook, token: first)
        #expect(tabs.claim(notebook, token: second))
    }

    @Test func infinitePageGrowsWithTheDrawing() throws {
        let f = try EditorFixture(sizing: .infinite(initial: CGSize(width: 1_000, height: 1_000)))
        let page = try f.page()
        page.setDrawing(PKDrawing(strokes: [TestInk.stroke(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 3_000, y: 2_500))]),
                        undoName: "Draw")
        f.session.growInfinitePageIfNeeded(page)
        #expect(page.pageSize.width >= 3_000 && page.pageSize.height >= 2_500)
        #expect(f.services.pages.page(id: page.pageID)?.widthPts == Double(page.pageSize.width))
    }
}
