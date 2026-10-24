import PencilKit
import SwiftUI
import Testing
import UIKit
import SheafnoteCore
@testable import Sheafnote

@MainActor
@Suite struct SelectionAndToolsTests {
    private func selected(_ f: EditorFixture, indices: [Int]) throws -> (PageSession, SelectionModel) {
        let page = try f.page()
        page.setDrawing(PKDrawingFactory.two(), undoName: "Draw")
        let ids = page.strokeIDs
        let model = f.session.selection
        let bounds = PKDrawing(strokes: indices.map { page.drawing.strokes[$0] }).bounds
        model.select(pageID: page.pageID, strokeIDs: Set(indices.map { ids[$0] }), elementIDs: [], bounds: bounds)
        return (page, model)
    }

    @Test func moveIsOneUndoStepAndKeepsTheSelection() async throws {
        let f = try EditorFixture()
        let (page, selection) = try selected(f, indices: [0])
        let oldBounds = try #require(selection.bounds)
        await EditorFixture.settle()

        try f.session.transformer.apply(CGAffineTransform(translationX: 50, y: 10), to: selection, in: page)
        #expect(page.drawing.strokes[0].transform.tx == 50 && page.drawing.strokes[0].transform.ty == 10)
        #expect(page.drawing.strokes[1].transform == .identity)
        #expect(selection.strokeIDs == [page.strokeIDs[0]])
        #expect(selection.bounds == oldBounds.offsetBy(dx: 50, dy: 10))

        await EditorFixture.settle()
        f.session.undo()
        #expect(page.drawing.strokes[0].transform == .identity)
        #expect(page.drawing.strokes.count == 2)
    }

    @Test func scaleAndRotateChangeTheStrokeTransform() throws {
        let f = try EditorFixture()
        let (page, selection) = try selected(f, indices: [0, 1])
        let center = CGPoint(x: selection.bounds!.midX, y: selection.bounds!.midY)
        try f.session.transformer.apply(SelectionGeometry.about(center, CGAffineTransform(scaleX: 2, y: 2)), to: selection, in: page)
        #expect(abs(page.drawing.strokes[0].transform.a - 2) < 1e-9)
        try f.session.transformer.apply(SelectionGeometry.about(center, CGAffineTransform(rotationAngle: .pi / 2)), to: selection, in: page)
        #expect(abs(page.drawing.strokes[0].transform.b) > 1)
    }

    @Test func recolorChangesInkColorAndIDs() async throws {
        let f = try EditorFixture()
        let (page, selection) = try selected(f, indices: [1])
        let oldID = page.strokeIDs[1]
        await EditorFixture.settle()
        try f.session.transformer.recolor(selection: selection, to: "#00FF00", in: page)
        #expect(page.drawing.strokes[1].ink.color.hexString == "#00FF00")
        #expect(page.drawing.strokes[1].ink.inkType == .pen)
        #expect(page.strokeIDs[1] != oldID)
        #expect(selection.strokeIDs == [page.strokeIDs[1]])
        #expect(page.drawing.strokes[0].ink.color.hexString == "#000000")
    }

    @Test func setWidthScalesStrokeSize() throws {
        let f = try EditorFixture()
        let (page, selection) = try selected(f, indices: [0])
        try f.session.transformer.setWidth(selection: selection, to: 12, in: page)
        let widths = page.drawing.strokes[0].path.map { Double($0.size.width) }
        #expect(abs((widths.reduce(0, +) / Double(widths.count)) - 12) < 0.01)
        #expect(page.drawing.strokes[0].path.count == 13)
    }

    @Test func deleteRemovesSelectedAndUndoRestores() async throws {
        let f = try EditorFixture()
        let (page, selection) = try selected(f, indices: [0])
        await EditorFixture.settle()
        try f.session.transformer.delete(selection: selection, in: page)
        #expect(page.drawing.strokes.count == 1 && selection.isEmpty)
        await EditorFixture.settle()
        f.session.undo()
        #expect(page.drawing.strokes.count == 2)
    }

    @Test func duplicateAddsOffsetCopiesWithDistinctIDs() throws {
        let f = try EditorFixture()
        let (page, selection) = try selected(f, indices: [0])
        let snapshot = try f.session.transformer.duplicate(selection: selection, in: page, offset: .zero)
        #expect(page.drawing.strokes.count == 3)
        #expect(Set(page.strokeIDs).count == 3)
        #expect(try PKDrawing(data: snapshot.strokes).strokes.count == 1)
        #expect(snapshot.bounds.minX > (selection.bounds?.minX ?? 0))
    }

    @Test func transformsMoveSelectedElementsToo() async throws {
        let f = try EditorFixture()
        let page = try f.page()
        let element = ElementValue(id: UUID(), pageID: page.pageID, kind: .sticker, frame: CGRect(x: 100, y: 100, width: 50, height: 50),
                                   rotation: 0, zIndex: 1, payload: Data(), assetID: nil)
        try page.elements.add(element, undoName: "Add")
        await EditorFixture.settle()
        f.session.selection.select(pageID: page.pageID, strokeIDs: [], elementIDs: [element.id], bounds: element.frame)
        try f.session.transformer.apply(CGAffineTransform(translationX: 30, y: 0), to: f.session.selection, in: page)
        #expect(page.elementValues.first?.frame.origin.x == 130)
        await EditorFixture.settle()
        f.session.undo()
        #expect(page.elementValues.first?.frame.origin.x == 100)
    }

    // MARK: Elements

    @Test func elementAddUpdateRemoveWithUndo() async throws {
        let f = try EditorFixture()
        let page = try f.page()
        let element = ElementValue(id: UUID(), pageID: page.pageID, kind: .text, frame: CGRect(x: 10, y: 10, width: 80, height: 30),
                                   rotation: 0, zIndex: 0, payload: Data("{}".utf8), assetID: nil)
        try page.elements.add(element, undoName: "Add")
        #expect(page.elements.all.count == 1)
        await EditorFixture.settle()
        try page.elements.update(id: element.id, undoName: "Edit") { $0.frame.origin.x = 55 }
        #expect(page.elements.all.first?.frame.origin.x == 55)
        await EditorFixture.settle()
        try page.elements.remove(ids: [element.id], undoName: "Delete")
        #expect(page.elements.all.isEmpty)
        #expect(f.services.pages.page(id: page.pageID) != nil)
        await EditorFixture.settle()
        f.session.undo()   // restores the deleted element
        #expect(page.elements.all.count == 1)
        await EditorFixture.settle()
        f.session.undo()   // reverts the move
        #expect(page.elements.all.first?.frame.origin.x == 10)
    }

    // MARK: Tool switching, Pencil, eraser

    @Test func doubleTapTogglesEraserAndBack() throws {
        let f = try EditorFixture()
        #expect(f.session.toolState.activeToolID == .pen)
        f.session.handlePencil(.doubleTap)
        #expect(f.session.toolState.activeToolID == .eraser)
        f.session.handlePencil(.doubleTap)
        #expect(f.session.toolState.activeToolID == .pen)
    }

    @Test func pencilSettingsSelectTheAction() throws {
        let f = try EditorFixture()
        f.session.prefs.values.doubleTap = .showPalette
        f.session.handlePencil(.doubleTap)
        #expect(f.session.paletteRequest == 1)
        f.session.prefs.values.squeeze = .switchToPrevious
        f.session.toolState.select(.highlighter)
        f.session.handlePencil(.squeeze)
        #expect(f.session.toolState.activeToolID == .pen)
        f.session.prefs.values.doubleTap = .off
        f.session.handlePencil(.doubleTap)
        #expect(f.session.toolState.activeToolID == .pen && f.session.paletteRequest == 1)
    }

    @Test func activeToolMayConsumeThePencilEvent() throws {
        final class Consumer: EditorTool {
            let id: ToolID = "consumer"; let title: LocalizedStringResource = "c"; let symbolName = "pencil"
            let placement = ToolPlacement.more(order: 1); let supportedKinds: Set<NotebookKind> = [.paged]
            let inputPolicy = ToolInputPolicy.overlayCapturesAll
            var seen: [PencilAction] = []
            func makeOptionsView(in editor: EditorContext) -> AnyView { AnyView(EmptyView()) }
            func handlePencilAction(_ action: PencilAction, in editor: EditorContext) -> Bool { seen.append(action); return true }
        }
        let f = try EditorFixture()
        let tool = Consumer()
        f.host.tools.register(tool)
        f.session.toolState.select("consumer")
        f.session.handlePencil(.doubleTap)
        #expect(tool.seen == [.doubleTap])
        #expect(f.session.toolState.activeToolID == "consumer")   // not switched to the eraser
    }

    @Test func switchBackAfterErasingOnlyWhenEnabled() throws {
        let f = try EditorFixture()
        f.session.toolState.select(.highlighter)
        f.session.toolState.select(.eraser)
        f.session.canvasEndedUsingTool()
        #expect(f.session.toolState.activeToolID == .eraser)
        f.session.prefs.values.eraserSwitchBack = true
        f.session.canvasEndedUsingTool()
        #expect(f.session.toolState.activeToolID == .highlighter)
    }

    @Test func toolActivationFollowsSelection() async throws {
        final class Spy: EditorTool {
            let id: ToolID = "spy"; let title: LocalizedStringResource = "s"; let symbolName = "pencil"
            let placement = ToolPlacement.more(order: 2); let supportedKinds: Set<NotebookKind> = [.paged]
            let inputPolicy = ToolInputPolicy.overlayCapturesAll
            var events: [String] = []
            func makeOptionsView(in editor: EditorContext) -> AnyView { AnyView(EmptyView()) }
            func activate(in editor: EditorContext) { events.append("on") }
            func deactivate(in editor: EditorContext) { events.append("off") }
        }
        let f = try EditorFixture()
        let spy = Spy()
        f.host.tools.register(spy)
        f.session.toolState.select("spy")
        await EditorFixture.settle()
        f.session.toolState.select(.pen)
        await EditorFixture.settle()
        #expect(spy.events == ["on", "off"])
    }

    @Test func inputModeFollowsPreferencesBothWays() async throws {
        let f = try EditorFixture()
        f.session.toolState.inputMode = .pencilOnly
        await EditorFixture.settle()
        #expect(f.session.prefs.inputMode == .pencilOnly)
        f.session.prefs.inputMode = .anyInput
        await EditorFixture.settle()
        #expect(f.session.toolState.inputMode == .anyInput)
    }

    @Test func selectingAnInkToolClearsTheSelection() async throws {
        let f = try EditorFixture()
        f.session.selection.select(pageID: UUID(), strokeIDs: [StrokeID(rawValue: "a")], elementIDs: [], bounds: .zero)
        f.session.toolState.select(.highlighter)
        await EditorFixture.settle()
        #expect(f.session.selection.isEmpty)
    }

    @Test func toolConfigurationChangesWithToolsAndPresets() throws {
        let f = try EditorFixture()
        let a = f.session.toolConfiguration
        f.session.toolState.select(.eraser)
        #expect(f.session.toolConfiguration != a)
        let b = f.session.toolConfiguration
        f.session.presetStore.selectWidth(index: 0, for: .eraser)
        #expect(f.session.toolConfiguration != b)
    }

    @Test func registeredToolsAreBuiltInOrderedAndSupportPagedAndWhiteboard() throws {
        let f = try EditorFixture()
        #expect(f.host.tools.tools(for: .paged).map(\.id) == [.pen, .eraser, .highlighter])
        #expect(f.host.tools.tools(for: .whiteboard).count == 3)
        #expect(f.host.tools.tools(for: .text).isEmpty)
        #expect(f.host.settings.sections.contains { $0.id == "editor.pencil" && $0.order == 10 })
        #expect(f.host.documents.editor(for: f.notebook, host: f.host) is AnyView)
    }

    @Test func optionsAccessoriesAreAppendedToTheRow() throws {
        let f = try EditorFixture()
        EditorOptionsAccessories.register(for: .highlighter) { _ in AnyView(Text("straight")) }
        #expect(EditorOptionsAccessories.views(for: .highlighter, editor: f.session).count == 1)
        #expect(EditorOptionsAccessories.views(for: .eraser, editor: f.session).isEmpty)
    }
}
