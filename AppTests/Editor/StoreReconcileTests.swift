import PencilKit
import SwiftData
import Testing
import UIKit
import SheafnoteCore
@testable import Sheafnote

@MainActor
@Suite struct StoreReconcileTests {
    private func extra(_ y: CGFloat, color: UIColor = .red, seconds: TimeInterval = 5_000) -> PKStroke {
        TestInk.stroke(from: CGPoint(x: 40, y: y), to: CGPoint(x: 280, y: y), color: color, width: 5,
                       date: Date(timeIntervalSinceReferenceDate: seconds))
    }

    /// What another device's ink looks like once sync wrote it into the store.
    private func writeRemoteInk(_ drawing: PKDrawing, to pageID: UUID, in f: EditorFixture) throws {
        try f.services.pages.saveInk(pageID: pageID, drawingData: drawing.dataRepresentation(), strokeIDs: drawing.strokeIDs)
    }

    @Test func remoteInkIsShownAndNotOverwrittenByTheNextAutosave() throws {
        let f = try EditorFixture()
        let page = try f.page()
        let base = PKDrawingFactory.one()
        page.setDrawing(base, undoName: "Draw")
        page.flush()
        let remote = PKDrawing(strokes: base.strokes + [extra(400)])
        try writeRemoteInk(remote, to: page.pageID, in: f)

        f.session.serverChangesApplied()
        #expect(page.drawing.strokes.count == 2)

        // The user keeps writing: the save must include the remote stroke.
        page.setDrawing(PKDrawing(strokes: page.drawing.strokes + [extra(500, seconds: 6_000)]), undoName: "Draw")
        page.flush()
        let stored = try #require(f.services.pages.page(id: page.pageID))
        #expect(stored.strokeIDs.count == 3)
    }

    @Test func unsavedStrokesAreMergedWithRemoteInkAndNothingIsLost() throws {
        let f = try EditorFixture()
        let page = try f.page()
        let base = PKDrawingFactory.one()
        page.setDrawing(base, undoName: "Draw")
        page.flush()
        try writeRemoteInk(PKDrawing(strokes: base.strokes + [extra(400, seconds: 5_000)]), to: page.pageID, in: f)
        page.setDrawing(PKDrawing(strokes: base.strokes + [extra(500, color: .blue, seconds: 6_000)]), undoName: "Draw")
        #expect(page.saver.hasUnsavedChanges)

        f.session.serverChangesApplied()

        #expect(page.drawing.strokes.count == 3)
        #expect(!page.saver.hasUnsavedChanges)
        let stored = try #require(f.services.pages.page(id: page.pageID))
        #expect(stored.strokeIDs.count == 3 && stored.syncDirty)
        let revisions = try f.services.context.fetch(FetchDescriptor<PageRevision>())
        #expect(revisions.contains { $0.reasonValue == .conflict && $0.strokeIDs.count == 2 })
    }

    @Test func aSaveNeverOverwritesRemoteInkWithAStaleDrawing() throws {
        let f = try EditorFixture()
        let page = try f.page()
        let base = PKDrawingFactory.one()
        page.setDrawing(base, undoName: "Draw")
        page.flush()
        try writeRemoteInk(PKDrawing(strokes: base.strokes + [extra(400)]), to: page.pageID, in: f)
        // No notification arrived yet; the debounced save fires with the stale in-memory drawing.
        page.setDrawing(PKDrawing(strokes: base.strokes + [extra(500, color: .blue, seconds: 6_000)]), undoName: "Draw")
        page.flush()
        let stored = try #require(f.services.pages.page(id: page.pageID))
        #expect(stored.strokeIDs.count == 3)
    }

    @Test func userEditThatEqualsAnEarlierProgrammaticStateIsStillSaved() throws {
        let f = try EditorFixture()
        let page = try f.page()
        _ = page.makeCanvas()
        let x = PKDrawingFactory.one()
        page.setDrawing(x, undoName: "Draw")
        page.flush()
        // The canvas echoes our own assignment, then the user draws a stroke and erases it again.
        page.canvasDrawingChanged(x)
        let withStroke = PKDrawing(strokes: x.strokes + [extra(400)])
        page.canvasDrawingChanged(withStroke)
        #expect(page.drawing.strokes.count == 2)
        page.canvasDrawingChanged(x)
        #expect(page.drawing.strokes.count == 1)
        #expect(page.saver.hasUnsavedChanges)
        page.flush()
        let stored = try #require(f.services.pages.page(id: page.pageID))
        #expect(stored.strokeIDs.count == 1)
    }

    @Test func pageWithUnsavedInkIsNotReleasedWhenTheSaveFails() throws {
        let f = try EditorFixture()
        let page = try f.page()
        page.setDrawing(PKDrawingFactory.one(), undoName: "Draw")
        let row = try #require(f.services.pages.page(id: page.pageID))
        f.services.context.delete(row)        // the store can no longer take this page's ink
        try f.services.context.save()
        #expect(!f.session.flushAll())
        f.session.releasePage(id: page.pageID)
        #expect(f.session.pageSessions[page.pageID] === page)
        #expect(f.session.hasUnsavedInk)
        let keeper = UnsavedInkKeeper(retryInterval: .seconds(3600))
        #expect(!keeper.settle(f.session))
        #expect(keeper.heldCount == 1)
    }

    @Test func pageWithStrokeIDsButNoInkBytesIsReadOnly() throws {
        let f = try EditorFixture()
        let row = try #require(f.services.pages.page(id: f.firstPageID))
        row.strokeIDs = ["x", "y"]
        row.inkData = Data()
        try f.services.context.save()
        let page = try f.page()
        #expect(!page.isEditable && page.loadProblem != nil)
    }
}
