import PencilKit
import SwiftUI
import Testing
import SheafnoteCore
@testable import Sheafnote

@MainActor
@Suite struct FoundationTests {
    func services() throws -> AppServices { try AppServices.inMemory() }

    @Test func toolRegistryOrdersByPlacementAndFiltersKinds() {
        final class T: EditorTool {
            let id: ToolID; let placement: ToolPlacement; let supportedKinds: Set<NotebookKind>
            let title: LocalizedStringResource = "t"; let symbolName = "pencil"; let inputPolicy = ToolInputPolicy.canvasHandlesInput
            init(_ id: ToolID, _ order: Int, _ kinds: Set<NotebookKind>) { self.id = id; placement = .primary(order: order); supportedKinds = kinds }
            func makeOptionsView(in editor: EditorContext) -> AnyView { AnyView(EmptyView()) }
        }
        let r = ToolRegistry()
        r.register(T(.eraser, 2, [.paged])); r.register(T(.pen, 1, [.paged, .whiteboard])); r.register(T(.text, 3, [.text]))
        #expect(r.tools(for: .paged).map(\.id) == [.pen, .eraser])
        #expect(r.tools(for: .whiteboard).map(\.id) == [.pen])
        #expect(r.tool(.text)?.id == .text)
    }

    @Test func toolStateRemembersPrevious() {
        let s = ToolState()
        s.select(.eraser); s.select(.eraser)
        #expect(s.activeToolID == .eraser && s.previousToolID == .pen)
    }

    @Test func hostBootstrapRegistersFoundationEntries() throws {
        let host = FeatureHost(services: try services())
        host.bootstrap()
        #expect(host.library.sortedNewItems.map(\.id).prefix(2) == ["notebook", "folder"])
        #expect(host.settings.sections.first?.id == "general" && host.settings.sections.last?.id == "about")
        #expect(host.library.backgroundTasks.contains { $0.id == "foundation.retention" })
        #expect(FeatureModules.all.count == 9)
    }

    @Test func routerShowsPlaceholderWhenNoFactory() throws {
        let s = try services()
        let host = FeatureHost(services: s)
        let nb = try s.library.createNotebook(title: "T", kind: .whiteboard, cover: .default, template: .blank,
                                              paperSize: .square, orientation: .portrait, paperColor: .white, in: nil)
        _ = host.documents.editor(for: nb, host: host)   // must not crash
    }

    @Test func selectionModel() {
        let m = SelectionModel()
        #expect(m.isEmpty)
        m.select(pageID: UUID(), strokeIDs: [StrokeID(rawValue: "a")], elementIDs: [], bounds: CGRect(x: 1, y: 1, width: 2, height: 2))
        #expect(!m.isEmpty && m.bounds != nil)
        m.clear()
        #expect(m.isEmpty && m.bounds == nil)
    }

    @Test func importRegistryMatchesByType() {
        let r = LibraryMenuRegistry()
        r.registerImportItem(LibraryImportHandler(id: "pdf", contentTypes: [.pdf]) { _, _ in })
        #expect(r.importHandler(for: URL(fileURLWithPath: "/tmp/a.pdf"))?.id == "pdf")
        #expect(r.importHandler(for: URL(fileURLWithPath: "/tmp/a.txt")) == nil)
        #expect(r.allImportTypes == [.pdf])
    }

    @Test func pageRendererDrawsPaper() async throws {
        let s = try services()
        let nb = try s.library.createNotebook(title: "T", kind: .paged, cover: .default, template: TemplateSpec(kind: .gridMedium),
                                              paperSize: .a4, orientation: .portrait, paperColor: .yellow, in: nil)
        let page = try #require(try s.pages.orderedPages(of: nb.id).first)
        let img = try await s.pageRenderer.renderImage(pageID: page.id, rect: nil, scale: 0.5, options: .screen)
        #expect(img.width == 298)
        let thumb = await s.pageRenderer.thumbnail(pageID: page.id, width: 100)
        #expect(thumb?.width == 100)
        await #expect(throws: PageRenderError.self) { _ = try await s.pageRenderer.renderImage(pageID: UUID(), rect: nil, scale: 1, options: .screen) }
    }

    @Test func elementLibrarySaveAndInsert() throws {
        let s = try services()
        let snapshot = SelectionSnapshot(strokes: PKDrawing().dataRepresentation(),
                                         elements: [ElementValue(pageID: UUID(), kind: .sticker, frame: CGRect(x: 100, y: 100, width: 40, height: 40))],
                                         bounds: CGRect(x: 100, y: 100, width: 40, height: 40))
        let saved = try s.elementLibrary.save(name: "S", category: "c", from: snapshot, thumbnail: Data([1]))
        #expect(saved.size == CGSize(width: 40, height: 40))
        #expect(try s.elementLibrary.all().count == 1)
        let page = FakePage()
        let result = try s.elementLibrary.insert(saved, into: page, at: CGPoint(x: 200, y: 200), scale: 2)
        #expect(result.bounds == CGRect(x: 160, y: 160, width: 80, height: 80))
        #expect(page.store.all.count == 1 && page.store.all[0].frame == CGRect(x: 160, y: 160, width: 80, height: 80))
        try s.elementLibrary.delete(id: saved.id)
        #expect(try s.elementLibrary.all().isEmpty)
    }

    @Test func paperDefaultsPersist() throws {
        let s = try services()
        #expect(s.settings.paperDefaults == .fallback)
        var d = PaperDefaults.fallback; d.color = .dark; d.size = .a5
        try s.settings.savePaperDefaults(d)
        #expect(s.settings.paperDefaults == d)
    }

    @Test func seedsAreDeterministic() throws {
        let s = try services()
        try UITestSeed.seed("libraryBasic", into: s)
        #expect(try s.library.allNotebooks().count == 3 && s.library.allFolders().count == 1)
        #expect(s.library.notebook(id: UITestSeed.fixedID(11))?.title == "Recipes")
        let p = try services()
        try UITestSeed.seed("pdfNotebook", into: p)
        #expect(try p.pages.orderedPages(of: UITestSeed.fixedID(30)).allSatisfy { $0.backgroundAssetID != nil })
        let t = try services()
        try UITestSeed.seed("notebookWith3Pages", into: t)
        #expect(try t.pages.orderedPages(of: UITestSeed.fixedID(20)).count == 3)
    }

    @Test func retentionJobPurgesOldTrash() throws {
        let s = try services()
        let nb = try s.library.createNotebook(title: "Old", kind: .paged, cover: .default, template: .blank,
                                              paperSize: .a4, orientation: .portrait, paperColor: .white, in: nil)
        try s.library.softDelete([.notebook(nb.id)], now: Date().addingTimeInterval(-31 * 86_400))
        FoundationRegistrations.runRetention(s)
        #expect(try s.library.allNotebooks().isEmpty)
    }

    @Test func displayHelpers() {
        #expect(PaperSize.a4.dimensionsText(units: .metric).contains("210"))
        #expect(PaperSize.letter.dimensionsText(units: .imperial).contains("8.5"))
        #expect(CoverCatalog.all.allSatisfy { String(localized: $0.title) != "Cover" })
    }
}

@MainActor
final class FakeElements: PageElementStore {
    var all: [ElementValue] = []
    func add(_ element: ElementValue, undoName: LocalizedStringResource) throws -> ElementValue { all.append(element); return element }
    func update(id: UUID, undoName: LocalizedStringResource, _ mutate: (inout ElementValue) -> Void) throws {}
    func remove(ids: Set<UUID>, undoName: LocalizedStringResource) throws {}
}

@MainActor
final class FakeInk: PageInkAccess {
    var strokes: [IdentifiedStroke] = []
    var lastInkTouchDate: Date?
    func edit(_ name: LocalizedStringResource, _ body: (inout [PKStroke]) -> Void) {}
    func strokes(intersecting polygon: [CGPoint]) -> [IdentifiedStroke] { [] }
    func render(strokeIDs: Set<StrokeID>, scale: CGFloat) -> UIImage? { nil }
}

@MainActor
final class FakePage: PageContext {
    let notebookID = UUID(), pageID = UUID()
    let pageSize = CGSize(width: 595, height: 842), zoomScale: CGFloat = 1
    let store = FakeElements(), fakeInk = FakeInk()
    var ink: any PageInkAccess { fakeInk }
    var elements: any PageElementStore { store }
    let undoManager = UndoManager()
    func pageToScreen(_ rect: CGRect) -> CGRect { rect }
    func screenToPage(_ point: CGPoint) -> CGPoint { point }
}
