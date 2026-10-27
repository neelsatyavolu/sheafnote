import Observation
import PencilKit
import SwiftUI
import UIKit
import SheafnoteCore

/// Live state of one page that is open in the editor: its drawing, elements, canvas and autosave.
/// Created lazily when the page comes near the viewport and released (after a flush) when it leaves.
@MainActor @Observable
final class PageSession: PageContext {
    @ObservationIgnored unowned let notebook: NotebookSession
    let pageID: UUID
    let notebookID: UUID

    private(set) var pageSize: CGSize
    private(set) var snapshot: PageSnapshot
    private(set) var drawing: PKDrawing
    private(set) var elementValues: [ElementValue] = []
    /// Set when the stored ink could not be decoded. The page then stays read-only so the stored bytes are never overwritten.
    private(set) var loadProblem: String?
    private(set) var drawingVersion = 0
    private(set) var lastInkTouchDate: Date?
    /// Bumped when paper, template or background changed so layer views rebuild.
    private(set) var layersRevision = 0
    /// True while selected strokes are lifted off the canvas for a drag preview.
    private(set) var isLifted = false

    @ObservationIgnored var canvas: InkCanvasView?
    @ObservationIgnored weak var container: PageContainerView?
    @ObservationIgnored private let canvasDelegate = CanvasDelegate()
    @ObservationIgnored private(set) lazy var inkAccess = PageInk(page: self)
    @ObservationIgnored private(set) lazy var elementStore = PageElements(page: self)
    @ObservationIgnored let saver = InkSaveScheduler()
    @ObservationIgnored private var echoDrawing: PKDrawing?
    /// The drawing when a Standard-eraser gesture began; nil otherwise.
    @ObservationIgnored private var eraseStart: PKDrawing?
    /// `inkHash` and stroke ids of the stored ink the editor last loaded or saved: what sync is compared against.
    @ObservationIgnored var storedInkHash: String
    @ObservationIgnored var storedStrokeIDs: [String]
    @ObservationIgnored private var cachedIDs: (version: Int, ids: [StrokeID])?

    var services: AppServices { notebook.services }
    var isEditable: Bool { loadProblem == nil }
    var zoomScale: CGFloat { notebook.zoomScale }
    var ink: any PageInkAccess { inkAccess }
    var elements: any PageElementStore { elementStore }
    var undoManager: UndoManager { notebook.undoManager }

    init?(notebook: NotebookSession, pageID: UUID) {
        guard let page = notebook.services.pages.page(id: pageID), page.deletedAt == nil else { return nil }
        self.notebook = notebook
        self.pageID = pageID
        self.notebookID = notebook.notebook.id
        self.pageSize = page.size
        self.snapshot = PageSnapshotFactory.make(page: page, notebook: notebook.notebook)
        self.storedInkHash = page.inkHash
        self.storedStrokeIDs = page.strokeIDs
        let loaded: PKDrawing
        (loaded, loadProblem) = Self.load(page)
        self.drawing = loaded
        canvasDelegate.page = self
        saver.owner = self
        reloadElements()
    }

    /// Decodes the stored ink. A page that claims strokes but has no ink bytes (a download that did not arrive) or whose
    /// bytes cannot be read stays read-only, so the next save never overwrites what may still be recoverable.
    static func load(_ page: Page) -> (drawing: PKDrawing, problem: String?) {
        if let data = page.inkData, !data.isEmpty {
            do { return (try PKDrawing(data: data), nil) } catch {
                return (PKDrawing(), String(localized: "The ink on this page could not be read. It has been left untouched, and this page is read-only.",
                                            table: "Editor"))
            }
        }
        guard page.strokeIDs.isEmpty else {
            return (PKDrawing(), String(localized: "The ink on this page has not arrived from iCloud yet. This page is read-only until it does.",
                                        table: "Editor"))
        }
        return (PKDrawing(), nil)
    }

    // MARK: Canvas

    func makeCanvas() -> InkCanvasView {
        if let canvas { return canvas }
        let c = InkCanvasView()
        c.drawing = drawing
        c.delegate = canvasDelegate
        c.isOpaque = false
        c.backgroundColor = .clear
        c.overrideUserInterfaceStyle = .light
        c.isScrollEnabled = false
        c.bounces = false
        c.contentInsetAdjustmentBehavior = .never
        c.frame = CGRect(origin: .zero, size: pageSize)
        c.isUserInteractionEnabled = isEditable
        canvas = c
        return c
    }

    func canvasDrawingChanged(_ new: PKDrawing) {
        guard isEditable, !isLifted, !Self.same(new, drawing) else { return }
        // The echo of a programmatic assignment is skipped at most once. A later user edit that happens to produce
        // the same drawing (undo, draw, erase) must still be saved.
        if let echo = echoDrawing {
            echoDrawing = nil
            if Self.same(new, echo) { return }
        }
        let old = drawing
        drawing = new
        let name = new.strokes.count > old.strokes.count ? "Draw" : "Erase"
        registerDrawingUndo(old: old, name: name)
        inkChanged()
        notebook.inkDidChangeFromCanvas(on: self)
    }

    func canvasBeganUsingTool() {
        lastInkTouchDate = .now
        let prefs = notebook.prefs.values
        let cleansUp = notebook.toolState.activeToolID == .eraser && prefs.eraserMode == .standard && !prefs.eraserHighlighterOnly
        eraseStart = cleansUp ? drawing : nil
    }

    /// Standard eraser: once the erase has landed, drops the crumbs it left of the strokes it cut.
    func canvasEndedUsingTool() {
        guard let start = eraseStart else { return }
        eraseStart = nil
        Task { @MainActor [weak self] in self?.removeEraseCrumbs(since: start) }
    }

    private func removeEraseCrumbs(since start: PKDrawing) {
        guard let canvas, isEditable, !isLifted else { return }
        let erased = canvas.drawing
        // Make sure the erase itself is recorded before tidying it.
        if !Self.same(erased, drawing) { canvasDrawingChanged(erased) }
        let cleaned = EraseCrumbs.removing(from: erased, since: start)
        guard cleaned.strokes.count != erased.strokes.count else { return }
        // No undo step of its own: undoing the erase brings back the cut strokes whole, crumbs included.
        setDrawingTransient(cleaned)
    }

    /// Replaces the drawing as one undoable edit and mirrors it into the live canvas.
    func setDrawing(_ new: PKDrawing, undoName: String) {
        guard isEditable else { return }
        let old = drawing
        drawing = new
        showInCanvas(new)
        registerDrawingUndo(old: old, name: undoName)
        inkChanged()
    }

    /// Updates drawing and canvas without registering undo; the caller registers one step for the whole gesture.
    func setDrawingTransient(_ new: PKDrawing) {
        guard isEditable else { return }
        drawing = new
        showInCanvas(new)
        inkChanged()
    }

    func registerDrawingUndo(old: PKDrawing, name: String) {
        let pageID = pageID
        let session = notebook
        session.undoManager.registerMain(target: session) { s in
            s.pageSession(for: pageID)?.setDrawing(old, undoName: name)
        }
        if !session.undoManager.isUndoing, !session.undoManager.isRedoing {
            session.undoManager.setActionName(String(localized: String.LocalizationValue(name), table: "Editor"))
        }
    }

    /// Hides the selected strokes in the canvas and returns an image of them for the drag preview. The stored drawing
    /// is untouched, so a cancelled drag (or `endLift`) always restores the canvas exactly.
    func beginLift(strokeIDs liftIDs: Set<StrokeID>, scale: CGFloat) -> (image: UIImage, rect: CGRect)? {
        guard isEditable, !isLifted, let image = inkAccess.render(strokeIDs: liftIDs, scale: scale) else { return nil }
        let ids = liftIDs
        let lifted = zip(self.strokeIDs, drawing.strokes).filter { ids.contains($0.0) }.map(\.1)
        let rect = PKDrawing(strokes: lifted).bounds.insetBy(dx: -4, dy: -4)
        let remaining = zip(self.strokeIDs, drawing.strokes).filter { !ids.contains($0.0) }.map(\.1)
        isLifted = true
        showInCanvas(PKDrawing(strokes: remaining))
        return (image, rect)
    }

    func endLift() {
        guard isLifted else { return }
        isLifted = false
        showInCanvas(drawing)
    }

    /// Every programmatic change to the canvas goes through here so its delegate echo is not mistaken for user ink.
    private func showInCanvas(_ new: PKDrawing) {
        echoDrawing = new
        canvas?.drawing = new
    }

    /// Resolves echoes of our own programmatic assignments: PencilKit reports them through the delegate too.
    static func same(_ a: PKDrawing, _ b: PKDrawing) -> Bool {
        a.strokes.count == b.strokes.count && a.bounds == b.bounds && a.dataRepresentation() == b.dataRepresentation()
    }

    // MARK: Store changes

    /// Shows ink that sync wrote into the store. Not an edit: no undo step, nothing to save.
    func replaceDrawingFromStore(_ new: PKDrawing) {
        drawing = new
        showInCanvas(new)
        drawingVersion += 1
        cachedIDs = nil
        container?.updateAccessibility()
        notebook.undoManager.removeAllActions()
        if notebook.selection.pageID == pageID { notebook.selection.clear() }
        NotificationCenter.default.post(name: EditorNotifications.inkDidChange, object: pageID)
    }

    func clearLoadProblem() {
        loadProblem = nil
        canvas?.isUserInteractionEnabled = true
    }

    /// The stored ink changed to something unreadable: keep what is on screen but stop writing over it.
    func markUnreadable() {
        loadProblem = String(localized: "The ink on this page could not be read. It has been left untouched, and this page is read-only.",
                             table: "Editor")
        canvas?.isUserInteractionEnabled = false
    }

    // MARK: Ink bookkeeping

    private func inkChanged() {
        drawingVersion += 1
        cachedIDs = nil
        container?.updateAccessibility()
        saver.markChanged()
        notebook.growInfinitePageIfNeeded(self)
        NotificationCenter.default.post(name: EditorNotifications.inkDidChange, object: pageID)
    }

    var strokeIDs: [StrokeID] {
        if let cachedIDs, cachedIDs.version == drawingVersion { return cachedIDs.ids }
        let ids = drawing.strokeIDs
        cachedIDs = (drawingVersion, ids)
        return ids
    }

    /// Writes any unsaved ink now. Called when the page leaves the viewport, the app backgrounds or the editor closes.
    @discardableResult
    func flush() -> Bool { saver.flushNow() }

    // MARK: Elements and layers

    func reloadElements() {
        do {
            elementValues = try services.pages.elements(on: pageID)
        } catch {
            notebook.report(error)
        }
    }

    /// Re-reads paper, template and size after a page operation changed them.
    func refreshSnapshot() {
        guard let page = services.pages.page(id: pageID) else { return }
        pageSize = page.size
        snapshot = PageSnapshotFactory.make(page: page, notebook: notebook.notebook)
        layersRevision += 1
        canvas?.frame = CGRect(origin: .zero, size: pageSize)
    }

    func resize(to size: CGSize) {
        guard size != pageSize else { return }
        pageSize = size
        snapshot = PageSnapshot(pageID: snapshot.pageID, notebookID: snapshot.notebookID, size: size,
                                backgroundAssetID: snapshot.backgroundAssetID, backgroundPageIndex: snapshot.backgroundPageIndex,
                                template: snapshot.template, paperColor: snapshot.paperColor)
        canvas?.frame = CGRect(origin: .zero, size: size)
        layersRevision += 1
    }

    // MARK: PageContext

    func pageToScreen(_ rect: CGRect) -> CGRect {
        guard let container else { return rect }
        return container.convert(rect, to: container.window)
    }

    func screenToPage(_ point: CGPoint) -> CGPoint {
        guard let container else { return point }
        return container.convert(point, from: container.window)
    }
}

enum PageSnapshotFactory {
    static func make(page: Page, notebook: Notebook) -> PageSnapshot {
        PageSnapshot(pageID: page.id, notebookID: page.notebookID, size: page.size,
                     backgroundAssetID: page.backgroundAssetID, backgroundPageIndex: page.backgroundPageIndex,
                     template: page.template ?? notebook.template,
                     paperColor: page.paperColorOverrideValue ?? notebook.paperColorValue)
    }
}

/// `PKCanvasView` that keeps PencilKit's own undo out of the picture: the notebook's single undo manager records edits.
final class InkCanvasView: PKCanvasView {
    private let privateUndo: UndoManager = {
        let manager = UndoManager()
        manager.disableUndoRegistration()
        return manager
    }()

    override var undoManager: UndoManager? { privateUndo }
}

@MainActor
final class CanvasDelegate: NSObject, PKCanvasViewDelegate {
    weak var page: PageSession?

    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        page?.canvasDrawingChanged(canvasView.drawing)
    }

    func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) {
        page?.canvasBeganUsingTool()
    }

    func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) {
        page?.canvasEndedUsingTool()
        page?.notebook.canvasEndedUsingTool()
    }
}
