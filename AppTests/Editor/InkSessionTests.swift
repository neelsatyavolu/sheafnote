import PencilKit
import Testing
import UIKit
import SheafnoteCore
@testable import Sheafnote

enum PKDrawingFactory {
    static func one(color: UIColor = .black) -> PKDrawing {
        PKDrawing(strokes: [TestInk.stroke(from: CGPoint(x: 50, y: 100), to: CGPoint(x: 300, y: 140), color: color, width: 6)])
    }

    static func two() -> PKDrawing {
        PKDrawing(strokes: [
            TestInk.stroke(from: CGPoint(x: 50, y: 100), to: CGPoint(x: 300, y: 100), width: 6),
            TestInk.stroke(from: CGPoint(x: 50, y: 300), to: CGPoint(x: 300, y: 300), color: .red, width: 6,
                           date: Date(timeIntervalSinceReferenceDate: 2_000)),
        ])
    }
}

@MainActor
@Suite struct InkSessionTests {
    @Test func drawingIsUndoableAndRedoable() async throws {
        let f = try EditorFixture()
        let page = try f.page()
        page.setDrawing(PKDrawingFactory.one(), undoName: "Draw")
        #expect(page.drawing.strokes.count == 1)
        #expect(f.session.undoManager.canUndo)

        await EditorFixture.settle()
        f.session.undo()
        #expect(page.drawing.strokes.isEmpty)
        #expect(f.session.canRedo)
        f.session.redo()
        #expect(page.drawing.strokes.count == 1)
    }

    @Test func successiveEditsUndoOneAtATime() async throws {
        let f = try EditorFixture()
        let page = try f.page()
        page.setDrawing(PKDrawingFactory.one(), undoName: "Draw")
        await EditorFixture.settle()
        page.setDrawing(PKDrawingFactory.two(), undoName: "Draw")
        await EditorFixture.settle()
        f.session.undo()
        #expect(page.drawing.strokes.count == 1)
        f.session.undo()
        #expect(page.drawing.strokes.isEmpty)
    }

    @Test func undoSpansPageOperationsAndInkInOneStack() async throws {
        let f = try EditorFixture()
        let page = try f.page()
        page.setDrawing(PKDrawingFactory.one(), undoName: "Draw")
        await EditorFixture.settle()
        let added = try #require(f.session.addPage(.end, template: nil))
        await EditorFixture.settle()
        f.session.undo()   // the page add
        #expect(!f.session.pageIDs.contains(added))
        #expect(page.drawing.strokes.count == 1)
        f.session.undo()   // the ink
        #expect(page.drawing.strokes.isEmpty)
    }

    @Test func flushWritesInkAndStrokeIDsToTheStore() throws {
        let f = try EditorFixture()
        let page = try f.page()
        page.setDrawing(PKDrawingFactory.two(), undoName: "Draw")
        page.flush()
        let stored = try #require(f.services.pages.page(id: page.pageID))
        #expect(stored.strokeIDs == page.strokeIDs.map(\.rawValue))
        #expect(stored.strokeIDs.count == 2)
        #expect(!stored.inkHash.isEmpty)
        let restored = try PKDrawing(data: try #require(stored.inkData))
        #expect(restored.strokes.count == 2)
        #expect(stored.syncDirty)
    }

    @Test func autosaveWritesAfterOneSecondWithoutEdits() async throws {
        let f = try EditorFixture()
        let page = try f.page()
        page.setDrawing(PKDrawingFactory.one(), undoName: "Draw")
        #expect(f.services.pages.page(id: page.pageID)?.inkData == nil)   // not yet: debounced
        try await Task.sleep(for: .seconds(1.8))
        #expect(f.services.pages.page(id: page.pageID)?.inkData != nil)
        #expect(!page.saver.hasUnsavedChanges)
    }

    @Test func rapidEditsCoalesceIntoTheLatestVersion() async throws {
        let f = try EditorFixture()
        let page = try f.page()
        page.setDrawing(PKDrawingFactory.one(), undoName: "Draw")
        try await Task.sleep(for: .milliseconds(600))
        page.setDrawing(PKDrawingFactory.two(), undoName: "Draw")
        try await Task.sleep(for: .milliseconds(600))
        #expect(f.services.pages.page(id: page.pageID)?.inkData == nil)   // timer restarted by the second edit
        try await Task.sleep(for: .milliseconds(1_200))
        #expect(f.services.pages.page(id: page.pageID)?.strokeIDs.count == 2)
    }

    @Test func clearingAllInkSnapshotsFirst() async throws {
        let f = try EditorFixture()
        let page = try f.page()
        page.setDrawing(PKDrawingFactory.one(), undoName: "Draw")
        page.flush()
        await EditorFixture.settle()
        f.session.undo()
        page.flush()
        #expect(f.services.pages.page(id: page.pageID)?.strokeIDs.isEmpty == true)
        #expect(f.services.revisions.revisions(for: page.pageID).count == 1)
    }

    @Test func unreadableInkIsNeverOverwritten() throws {
        let f = try EditorFixture()
        let garbage = Data([1, 2, 3, 4])
        let model = try #require(f.services.pages.page(id: f.firstPageID))
        model.inkData = garbage
        try f.services.context.save()

        let page = try #require(PageSession(notebook: f.session, pageID: f.firstPageID))
        #expect(page.loadProblem != nil && !page.isEditable)
        page.setDrawing(PKDrawingFactory.one(), undoName: "Draw")
        #expect(page.drawing.strokes.isEmpty)
        page.flush()
        #expect(model.inkData == garbage)
    }

    @Test func editorPostsInkChangeNotifications() throws {
        let f = try EditorFixture()
        let page = try f.page()
        var received: [UUID] = []
        let token = NotificationCenter.default.addObserver(forName: EditorNotifications.inkDidChange, object: nil, queue: .main) { note in
            if let id = note.object as? UUID { received.append(id) }
        }
        defer { NotificationCenter.default.removeObserver(token) }
        page.setDrawing(PKDrawingFactory.one(), undoName: "Draw")
        #expect(received == [page.pageID])
    }

    @Test func pageInkAccessEditsAreUndoableWithFreshIDs() async throws {
        let f = try EditorFixture()
        let page = try f.page()
        page.setDrawing(PKDrawingFactory.two(), undoName: "Draw")
        let before = page.ink.strokes.map(\.id)
        #expect(before.count == 2)
        await EditorFixture.settle()
        page.ink.edit("Remove") { $0.removeFirst() }
        #expect(page.ink.strokes.map(\.id) == [before[1]])
        await EditorFixture.settle()
        f.session.undo()
        #expect(page.ink.strokes.map(\.id) == before)
    }

    @Test func lassoPolygonFindsStrokesByPathNotJustBounds() throws {
        let f = try EditorFixture()
        let page = try f.page()
        // A diagonal stroke: its bounding box covers the top-right corner, its path does not.
        let diagonal = TestInk.stroke(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 300, y: 300))
        page.setDrawing(PKDrawing(strokes: [diagonal]), undoName: "Draw")
        let corner = [CGPoint(x: 250, y: 100), CGPoint(x: 320, y: 100), CGPoint(x: 320, y: 150), CGPoint(x: 250, y: 150)]
        #expect(page.ink.strokes(intersecting: corner).isEmpty)
        let onPath = [CGPoint(x: 180, y: 180), CGPoint(x: 220, y: 180), CGPoint(x: 220, y: 220), CGPoint(x: 180, y: 220)]
        #expect(page.ink.strokes(intersecting: onPath).count == 1)
        #expect(page.ink.strokes(intersecting: []).isEmpty)
    }

    @Test func inkRenderForSelectionScreenshot() throws {
        let f = try EditorFixture()
        let page = try f.page()
        page.setDrawing(PKDrawingFactory.two(), undoName: "Draw")
        let ids = Set(page.ink.strokes.prefix(1).map(\.id))
        let image = try #require(page.ink.render(strokeIDs: ids, scale: 2))
        #expect(image.size.width > 200)
        #expect(page.ink.render(strokeIDs: [], scale: 2) == nil)
    }
}
