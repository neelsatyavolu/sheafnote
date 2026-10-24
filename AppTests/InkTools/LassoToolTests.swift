import PencilKit
import SwiftUI
import Testing
import UIKit
import SheafnoteCore
@testable import Sheafnote

@MainActor
@Suite struct InkToolsRegistrationTests {
    @Test func featureRegistersToolsRendererActionsObserversAndSettings() throws {
        let f = try InkToolsFixture()
        #expect(f.host.tools.tools(for: .paged).map(\.id) == [.pen, .eraser, .highlighter, .shapes, .lasso])
        #expect(f.host.tools.tools(for: .whiteboard).map(\.id).suffix(2) == [.shapes, .lasso])
        #expect(f.host.tools.tools(for: .text).isEmpty)
        #expect(f.host.elementRenderers.renderer(for: .shape) != nil)
        #expect(f.host.selectionActions.actions.map(\.id) == ["ink.copy", "ink.cut", "ink.duplicate", "ink.delete", "ink.style",
                                                              "ink.screenshot", "ink.convertText"])
        #expect(f.host.touchObservers.observers(for: .pen).count == 1)
        #expect(f.host.touchObservers.observers(for: .highlighter).count == 1)
        #expect(f.host.touchObservers.observers(for: .lasso).isEmpty)
        #expect(f.host.settings.sections.contains { $0.id == "ink-tools" && $0.order == 12 })
    }

    @Test func overlayToolsTakeTouchesAndFollowTheInputMode() throws {
        let f = try InkToolsFixture()
        #expect(f.lasso.inputPolicy == .overlayCapturesAll && f.shapes.inputPolicy == .overlayCapturesAll)
        f.session.toolState.inputMode = .pencilOnly
        #expect(f.lasso.inputPolicy == .overlayCapturesPencil && f.shapes.inputPolicy == .overlayCapturesPencil)
    }

    @Test func settingsPersistAcrossInstances() throws {
        let f = try InkToolsFixture()
        f.settings.setLassoFilters([.text])
        f.settings.updateShape { $0.mode = .arrow; $0.fillHex = "#00FF00"; $0.lineWidth = 6 }
        f.settings.setStraightHighlighter(true)
        f.settings.setDrawAndHold(false)
        let reloaded = InkToolsSettings(store: f.services.settings)
        #expect(reloaded.lassoFilters == [.text])
        #expect(reloaded.shape.mode == .arrow && reloaded.shape.fillHex == "#00FF00" && reloaded.shape.lineWidth == 6)
        #expect(reloaded.straightHighlighter && !reloaded.drawAndHold)
    }

    @Test func defaultsPickUpEverythingAndSnapOnHold() throws {
        let f = try InkToolsFixture()
        #expect(f.settings.lassoFilters == .all && f.settings.drawAndHold && !f.settings.straightHighlighter)
        #expect(f.settings.shape.mode == .auto)
    }

    @Test func toggleFlipsOneFilterOnly() throws {
        let f = try InkToolsFixture()
        f.settings.toggleLassoFilter(.images)
        #expect(f.settings.lassoFilters == [.handwriting, .text])
        f.settings.toggleLassoFilter(.images)
        #expect(f.settings.lassoFilters == .all)
    }
}

@MainActor
@Suite struct LassoToolTests {
    func twoStrokePage(_ f: InkToolsFixture) throws -> PageSession {
        let page = try f.page()
        page.setDrawing(PKDrawing(strokes: [InkSketch.line(CGPoint(x: 100, y: 100), CGPoint(x: 200, y: 140)),
                                            InkSketch.line(CGPoint(x: 400, y: 300), CGPoint(x: 480, y: 360))]), undoName: "Draw")
        return page
    }

    // MARK: Selecting

    @Test func loopSelectsOnlyTheStrokesItTouches() throws {
        let f = try InkToolsFixture()
        let page = try twoStrokePage(f)
        f.lasso.finish(InkSketch.loop(around: CGRect(x: 60, y: 60, width: 200, height: 140)), page: page, editor: f.session)
        #expect(f.session.selection.strokeIDs == [page.strokeIDs[0]])
        let bounds = try #require(f.session.selection.bounds)
        #expect(bounds.contains(CGPoint(x: 150, y: 120)) && !bounds.contains(CGPoint(x: 440, y: 330)))
    }

    @Test func aLoopCrossingPartOfAStrokeStillSelectsIt() throws {
        let f = try InkToolsFixture()
        let page = try twoStrokePage(f)
        f.lasso.finish(InkSketch.loop(around: CGRect(x: 130, y: 90, width: 40, height: 60)), page: page, editor: f.session)
        #expect(f.session.selection.strokeIDs == [page.strokeIDs[0]])
    }

    @Test func aLoopAroundNothingClearsTheSelectionAndSaysSo() throws {
        let f = try InkToolsFixture()
        let page = try twoStrokePage(f)
        f.select([0], on: page)
        f.lasso.finish(InkSketch.loop(around: CGRect(x: 250, y: 500, width: 100, height: 100)), page: page, editor: f.session)
        #expect(f.session.selection.isEmpty)
        #expect(f.session.toast != nil)
    }

    @Test func tappingAStrokeSelectsJustThatStroke() throws {
        let f = try InkToolsFixture()
        let page = try twoStrokePage(f)
        f.lasso.finish([CGPoint(x: 440, y: 330)], page: page, editor: f.session)
        #expect(f.session.selection.strokeIDs == [page.strokeIDs[1]])
        f.lasso.finish([CGPoint(x: 300, y: 600)], page: page, editor: f.session)
        #expect(f.session.selection.isEmpty)
    }

    @Test func aStraightDragSelectsNothing() throws {
        let f = try InkToolsFixture()
        let page = try twoStrokePage(f)
        f.lasso.finish(InkSketch.samples([CGPoint(x: 50, y: 120), CGPoint(x: 300, y: 120)], step: 5), page: page, editor: f.session)
        #expect(f.session.selection.isEmpty)
    }

    @Test func selectAllTakesEverythingTheFiltersAllow() throws {
        let f = try InkToolsFixture()
        let page = try twoStrokePage(f)
        try f.addShape(.rectangle(center: CGPoint(x: 300, y: 500), size: CGSize(width: 80, height: 60), rotation: 0), to: page)
        f.lasso.selectAll(page: page, editor: f.session)
        #expect(f.session.selection.strokeIDs.count == 2 && f.session.selection.elementIDs.count == 1)
        f.settings.toggleLassoFilter(.handwriting)   // handwriting covers strokes and shapes
        f.lasso.selectAll(page: page, editor: f.session)
        #expect(f.session.selection.isEmpty)
    }

    @Test func filtersKeepElementKindsOutOfTheLoop() throws {
        let f = try InkToolsFixture()
        let page = try f.page()
        let text = ElementValue(pageID: page.pageID, kind: .text, frame: CGRect(x: 100, y: 100, width: 100, height: 40), zIndex: 1)
        try page.elements.add(text, undoName: "Add")
        let loop = InkSketch.loop(around: CGRect(x: 50, y: 50, width: 250, height: 150))
        f.settings.setLassoFilters([.handwriting, .images])
        f.lasso.finish(loop, page: page, editor: f.session)
        #expect(f.session.selection.isEmpty)
        f.settings.setLassoFilters([.text])
        f.lasso.finish(loop, page: page, editor: f.session)
        #expect(f.session.selection.elementIDs == [text.id])
    }

    @Test func shapeSelectionFollowsTheOutlineNotTheBox() throws {
        let f = try InkToolsFixture()
        let page = try f.page()
        let line = try f.addShape(.line(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 300, y: 300)), to: page)
        f.lasso.finish(InkSketch.loop(around: CGRect(x: 240, y: 110, width: 50, height: 50)), page: page, editor: f.session)
        #expect(f.session.selection.isEmpty, "the empty corner of the line's box must not select it")
        f.lasso.finish(InkSketch.loop(around: CGRect(x: 180, y: 180, width: 50, height: 50)), page: page, editor: f.session)
        #expect(f.session.selection.elementIDs == [line.id])
        f.lasso.finish([CGPoint(x: 201, y: 199)], page: page, editor: f.session)
        #expect(f.session.selection.elementIDs == [line.id])
    }

    @Test func tappingPicksTheTopmostElementOverInk() throws {
        let f = try InkToolsFixture()
        let page = try twoStrokePage(f)
        let sticker = ElementValue(pageID: page.pageID, kind: .sticker, frame: CGRect(x: 120, y: 90, width: 100, height: 80), zIndex: 3)
        try page.elements.add(sticker, undoName: "Add")
        f.lasso.finish([CGPoint(x: 150, y: 120)], page: page, editor: f.session)
        #expect(f.session.selection.elementIDs == [sticker.id] && f.session.selection.strokeIDs.isEmpty)
    }

    @Test func leavingTheToolDropsTheSelection() throws {
        let f = try InkToolsFixture()
        let page = try twoStrokePage(f)
        f.select([0], on: page)
        f.lasso.deactivate(in: f.session)
        #expect(f.session.selection.isEmpty)
    }

    // MARK: What the editor does with the selection

    @Test func moveDeleteAndUndoWorkOnALassoSelection() async throws {
        let f = try InkToolsFixture()
        let page = try twoStrokePage(f)
        f.lasso.finish(InkSketch.loop(around: CGRect(x: 60, y: 60, width: 200, height: 140)), page: page, editor: f.session)
        let before = page.drawing.strokes[0].renderBounds
        await InkToolsFixture.settle()

        try f.session.transformer.apply(CGAffineTransform(translationX: 40, y: 25), to: f.session.selection, in: page)
        #expect(abs(page.drawing.strokes[0].renderBounds.minX - (before.minX + 40)) < 0.01)
        #expect(page.drawing.strokes[1].transform == .identity)
        await InkToolsFixture.settle()

        try f.session.transformer.delete(selection: f.session.selection, in: page)
        #expect(page.drawing.strokes.count == 1 && f.session.selection.isEmpty)
        await InkToolsFixture.settle()

        f.session.undo()
        #expect(page.drawing.strokes.count == 2)
        await InkToolsFixture.settle()
        f.session.undo()
        #expect(abs(page.drawing.strokes[0].renderBounds.minX - before.minX) < 0.01)
    }

    @Test func undoingAMoveDropsTheStaleSelection() async throws {
        let f = try InkToolsFixture()
        let page = try twoStrokePage(f)
        f.lasso.finish(InkSketch.loop(around: CGRect(x: 60, y: 60, width: 200, height: 140)), page: page, editor: f.session)
        await InkToolsFixture.settle()
        try f.session.transformer.apply(CGAffineTransform(translationX: 40, y: 25), to: f.session.selection, in: page)
        #expect(!f.session.selection.isEmpty)
        await InkToolsFixture.settle()
        f.session.undo()
        await InkToolsFixture.settle()
        #expect(f.session.selection.isEmpty, "the undone ink has its old ids, so the old selection no longer points at it")
    }

    @Test func aSelectionThatStillExistsSurvivesUndoOfSomethingElse() async throws {
        let f = try InkToolsFixture()
        let page = try twoStrokePage(f)
        await InkToolsFixture.settle()
        try page.elements.add(ElementValue(pageID: page.pageID, kind: .sticker, frame: CGRect(x: 10, y: 10, width: 30, height: 30), zIndex: 1),
                              undoName: "Add")
        await InkToolsFixture.settle()
        f.select([0], on: page)
        f.session.undo()
        await InkToolsFixture.settle()
        #expect(f.session.selection.strokeIDs == [page.strokeIDs[0]])
    }

    @Test func rotateAndResizeKeepEveryStroke() throws {
        let f = try InkToolsFixture()
        let page = try twoStrokePage(f)
        f.lasso.selectAll(page: page, editor: f.session)
        let bounds = try #require(f.session.selection.bounds)
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        try f.session.transformer.apply(SelectionGeometry.about(center, CGAffineTransform(rotationAngle: .pi / 6)), to: f.session.selection, in: page)
        try f.session.transformer.apply(SelectionGeometry.about(center, CGAffineTransform(scaleX: 1.5, y: 1.5)), to: f.session.selection, in: page)
        #expect(page.drawing.strokes.count == 2)
        #expect(f.session.selection.strokeIDs.count == 2 && Set(page.strokeIDs) == f.session.selection.strokeIDs)
    }
}
