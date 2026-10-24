import Foundation
import PencilKit
import SwiftUI
import Testing
import SheafnoteCore
@testable import Sheafnote

@MainActor
@Suite struct DocumentTypesTests {
    func make() throws -> (AppServices, FeatureHost) {
        let services = try AppServices.inMemory()
        return (services, FeatureHost(services: services))
    }

    // MARK: Creation and routing

    @Test func newItemsAreRegisteredAfterNotebookAndFolder() throws {
        let (services, host) = try make()
        FoundationRegistrations.register(into: host)
        host.library.registerNewItem(DocumentCreation.whiteboardItem)
        host.library.registerNewItem(DocumentCreation.textDocumentItem)
        #expect(host.library.sortedNewItems.map(\.id) == ["notebook", "folder", "whiteboard", "textDocument"])
        _ = services
    }

    @Test func whiteboardGetsOneInfinitePageOfAtLeastTheInitialSize() throws {
        let (services, _) = try make()
        let board = try DocumentCreation.make(kind: .whiteboard, title: "Board", cover: "blueprint", services: services, folder: nil)
        let pages = try services.pages.orderedPages(of: board.id)
        #expect(pages.count == 1)
        #expect(pages[0].isInfinite)
        #expect(pages[0].widthPts >= Whiteboard.initialSize.width)
        #expect(pages[0].heightPts >= Whiteboard.initialSize.height)
        #expect(board.kind == .whiteboard)
    }

    @Test func textDocumentHasNoPagesAndStartsEmpty() throws {
        let (services, _) = try make()
        let doc = try DocumentCreation.make(kind: .text, title: "Notes", cover: "ledger", services: services, folder: nil)
        #expect(try services.pages.orderedPages(of: doc.id).isEmpty)
        #expect(doc.richText == nil)
    }

    @Test func prepareCanvasGrowsToCoverExistingInkAndNeverShrinks() throws {
        let (services, _) = try make()
        let board = try DocumentCreation.make(kind: .whiteboard, title: "Board", cover: "blueprint", services: services, folder: nil)
        let page = try #require(try services.pages.orderedPages(of: board.id).first)
        let stroke = TestInk.stroke(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 3500, y: 200))
        let drawing = PKDrawing(strokes: [stroke])
        try services.pages.saveInk(pageID: page.id, drawingData: drawing.dataRepresentation(), strokeIDs: [StrokeID(rawValue: "s1")])
        try Whiteboard.prepareCanvas(for: board, services: services)
        let grown = try #require(services.pages.page(id: page.id))
        #expect(grown.widthPts >= 3500 + CanvasBounds.growthMargin)
        let width = grown.widthPts
        try Whiteboard.prepareCanvas(for: board, services: services)
        #expect(services.pages.page(id: page.id)?.widthPts == width)
        #expect(services.pages.inkData(pageID: page.id) != nil, "ink is untouched")
    }

    @Test func prepareCanvasRepairsAMissingPage() throws {
        let (services, _) = try make()
        let board = try services.library.createNotebook(title: "X", kind: .whiteboard, cover: .default, template: TemplateSpec(kind: .blank),
                                                        paperSize: .square, orientation: .portrait, paperColor: .white, in: nil)
        try services.pages.softDelete(pageIDs: try services.pages.orderedPages(of: board.id).map(\.id))
        try Whiteboard.prepareCanvas(for: board, services: services)
        #expect(try services.pages.orderedPages(of: board.id).count == 1)
    }

    @Test func routerUsesRegisteredFactoriesForBothKinds() throws {
        let (services, host) = try make()
        host.documents.register(WhiteboardEditorFactory())
        host.documents.register(TextDocumentEditorFactory())
        let board = try DocumentCreation.make(kind: .whiteboard, title: "B", cover: "blueprint", services: services, folder: nil)
        let text = try DocumentCreation.make(kind: .text, title: "T", cover: "ledger", services: services, folder: nil)
        _ = host.documents.editor(for: board, host: host)
        _ = host.documents.editor(for: text, host: host)
    }

    @Test func routerGateDecidesWhetherTheEditorIsBuilt() throws {
        let (services, host) = try make()
        var built = 0
        let factory = CountingFactory { built += 1 }
        host.documents.register(factory)
        let text = try DocumentCreation.make(kind: .text, title: "T", cover: "ledger", services: services, folder: nil)
        var allowed = false
        host.documents.gate = { _, content in
            allowed ? content() : AnyView(EmptyView())
        }
        _ = host.documents.editor(for: text, host: host)
        #expect(built == 0)
        allowed = true
        _ = host.documents.editor(for: text, host: host)
        #expect(built == 1)
    }

    @Test func registeringTheFeatureWiresEverythingIntoTheHost() throws {
        let (_, host) = try make()
        DocTypesFeature.register(into: host)
        #expect(host.documents.gate != nil)
        #expect(host.settings.sections.contains { $0.id == "appLock" && $0.order == 50 })
        #expect(host.library.newItems.map(\.id).sorted() == ["textDocument", "whiteboard"])
        #expect(host.library.notebookActions.contains { $0.id == "docTypes.lock" })
        #expect(host.notebookMenu.menuItems.contains { $0.id == "docTypes.showWholeBoard" && $0.kinds == [.whiteboard] })
    }

    // MARK: Per-notebook lock flag

    @Test func lockActionTogglesTheFlagAndMarksTheNotebookForSync() throws {
        let (services, _) = try make()
        let nb = try DocumentCreation.make(kind: .text, title: "T", cover: "ledger", services: services, folder: nil)
        nb.syncDirty = false
        nb.dirtyFields = []
        try NotebookLockAction.setLocked(true, [nb], services: services)
        #expect(nb.isLocked)
        #expect(nb.syncDirty && nb.dirtyFields.contains("isLocked"))
        try NotebookLockAction.setLocked(false, [nb], services: services)
        #expect(!nb.isLocked)
    }

    @Test func lockingNeverChangesContent() throws {
        let (services, _) = try make()
        let nb = try DocumentCreation.make(kind: .text, title: "T", cover: "ledger", services: services, folder: nil)
        nb.richText = RichTextDocument.empty.settingText("secret", for: RichTextDocument.empty.blocks[0].id).encoded()
        let before = nb.richText
        try NotebookLockAction.setLocked(true, [nb], services: services)
        #expect(nb.richText == before)
        #expect(nb.deletedAt == nil)
    }

    @Test func lockedNotebookUnlocksThroughTheActionAfterAuthentication() async throws {
        let (services, _) = try make()
        let nb = try DocumentCreation.make(kind: .text, title: "T", cover: "ledger", services: services, folder: nil)
        try NotebookLockAction.setLocked(true, [nb], services: services)
        let controller = AppLockController()
        controller.configure(settings: services.settings, authenticator: ScriptedAuthenticator(results: [.cancelled]))
        let context = LibraryActionContext(services: services, currentFolderID: nil, present: { _ in }, open: { _ in }, showError: { _ in })
        try await NotebookLockAction.toggle([nb], context: context, controller: controller)
        #expect(nb.isLocked, "a cancelled prompt must not remove the lock")
        controller.configure(settings: services.settings, authenticator: ScriptedAuthenticator(results: [.success]))
        try await NotebookLockAction.toggle([nb], context: context, controller: controller)
        #expect(!nb.isLocked)
    }
}

private struct CountingFactory: DocumentEditorFactory {
    let kind = NotebookKind.text
    let onBuild: () -> Void
    init(onBuild: @escaping () -> Void) { self.onBuild = onBuild }
    func makeEditor(for notebook: Notebook, host: FeatureHost) -> AnyView {
        onBuild()
        return AnyView(EmptyView())
    }
}
