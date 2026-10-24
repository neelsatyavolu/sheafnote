import Observation
import SwiftUI
import SheafnoteCore

/// What the notebook's canvas host offers the session (scrolling, zoom, which pages are on screen).
@MainActor
protocol NotebookViewport: AnyObject {
    var livePageIDs: [UUID] { get }
    var visiblePageIDs: [UUID] { get }
    func scrollToPage(id: UUID, animated: Bool)
    func setZoom(_ scale: CGFloat, animated: Bool)
}

struct ToastItem: Identifiable {
    let id = UUID()
    let message: LocalizedStringResource
}

struct EditorAlert: Identifiable {
    let id = UUID()
    let message: String
}

/// Everything about one open notebook: tools, presets, selection, the single undo manager, the ordered page list
/// and the live per-page sessions. Implements `EditorContext` for tools and feature modules.
@MainActor @Observable
final class NotebookSession: EditorContext {
    let notebook: Notebook
    let host: FeatureHost
    let sizing: PageSizing
    let toolState: ToolState
    let presetStore: EditorPresetStore
    let prefs: EditorPreferences
    let selection = SelectionModel()
    let undoManager = UndoManager()

    private(set) var pageIDs: [UUID] = []
    private(set) var pageSizes: [UUID: CGSize] = [:]
    /// Bumped whenever the page list, order or any page size changed, so the canvas host re-lays out.
    var layoutRevision = 0
    private(set) var currentPageID: UUID?
    private(set) var zoomScale: CGFloat = 1
    private(set) var canUndo = false
    private(set) var canRedo = false
    private(set) var scrollDirection: ScrollDirection
    var toast: ToastItem?
    var sheet: EditorSheet?
    var alert: EditorAlert?
    private(set) var saveFailure: String?
    /// Incremented by Pencil squeeze ("show palette"); the chrome opens the color popover when it changes.
    var paletteRequest = 0

    @ObservationIgnored private(set) lazy var transformer = SelectionTransformer(session: self)
    @ObservationIgnored var pageSessions: [UUID: PageSession] = [:]
    @ObservationIgnored weak var viewport: (any NotebookViewport)?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var activeToolSeen: ToolID
    @ObservationIgnored private var inputSeen: InputMode

    var services: AppServices { host.services }
    var presets: any ToolPresetStore { presetStore }
    var selectionTransformer: any SelectionTransforming { transformer }

    init(notebook: Notebook, host: FeatureHost, sizing: PageSizing = .fixed(.zero)) {
        self.notebook = notebook
        self.host = host
        self.sizing = sizing
        let prefs = EditorPreferences.shared ?? EditorPreferences(settings: host.services.settings)
        self.prefs = prefs
        self.presetStore = EditorPresetStore(settings: host.services.settings)
        self.toolState = ToolState(activeToolID: .pen, inputMode: prefs.inputMode)
        self.activeToolSeen = .pen
        self.inputSeen = prefs.inputMode
        self.scrollDirection = notebook.scrollDirectionValue
        undoManager.levelsOfUndo = 300
        observeUndo()
        observeServerChanges()
        observeTools()
        reloadPages()
        currentPageID = pageIDs.first
        host.tools.tool(.pen)?.activate(in: self)
        do { try services.library.recordOpened(notebook.id) } catch { report(error) }
    }

    isolated deinit {
        for token in observers { NotificationCenter.default.removeObserver(token) }
    }

    // MARK: Pages

    var currentPage: (any PageContext)? { currentPageID.flatMap { pageSession(for: $0) } }

    var visiblePages: [any PageContext] {
        (viewport?.visiblePageIDs ?? []).compactMap { pageSessions[$0] }
    }

    var currentPageNumber: Int { currentPageID.flatMap { pageIDs.firstIndex(of: $0) }.map { $0 + 1 } ?? 1 }

    func pageSession(for id: UUID) -> PageSession? {
        if let existing = pageSessions[id] { return existing }
        guard pageIDs.contains(id), let created = PageSession(notebook: self, pageID: id) else { return nil }
        pageSessions[id] = created
        return created
    }

    /// Writes the page's ink and forgets its live state. Undo steps look pages up again by id, so this is safe.
    func releasePage(id: UUID) {
        guard let page = pageSessions[id] else { return }
        // A page whose ink could not be written keeps its session: the retry needs it, and the strokes live only there.
        guard page.flush() else { return }
        if selection.pageID == id { selection.clear() }
        pageSessions[id] = nil
    }

    /// Writes every page's unsaved ink. Returns false when some of it could not be saved.
    @discardableResult
    func flushAll() -> Bool {
        pageSessions.values.map { $0.flush() }.allSatisfy { $0 }
    }

    var hasUnsavedInk: Bool { pageSessions.values.contains { $0.saver.hasUnsavedChanges } }

    func reloadPages() {
        do {
            let pages = try services.pages.orderedPages(of: notebook.id)
            if pages.isEmpty {
                _ = try services.pages.addPage(to: notebook.id, at: .end, template: nil)
                return reloadPages()
            }
            applyPages(pages)
        } catch {
            report(error)
        }
    }

    private func applyPages(_ pages: [Page]) {
        let visible: [Page]
        if case .infinite = sizing { visible = Array(pages.prefix(1)) } else { visible = pages }
        pageIDs = visible.map(\.id)
        pageSizes = Dictionary(uniqueKeysWithValues: visible.map { ($0.id, $0.size) })
        if let current = currentPageID, !pageIDs.contains(current) { currentPageID = pageIDs.first }
        for (id, session) in pageSessions where !pageIDs.contains(id) && session.flush() {
            pageSessions[id] = nil
        }
        layoutRevision += 1
    }

    func pageSizeChanged(_ id: UUID, to size: CGSize) {
        guard pageSizes[id] != size else { return }
        pageSizes[id] = size
        layoutRevision += 1
    }

    func setCurrentPage(_ id: UUID) {
        guard currentPageID != id else { return }
        currentPageID = id
    }

    func goToPage(id: UUID, animated: Bool) {
        guard pageIDs.contains(id) else { return }
        currentPageID = id
        viewport?.scrollToPage(id: id, animated: animated)
    }

    func goToPage(number: Int) {
        guard pageIDs.indices.contains(number - 1) else {
            showToast(LocalizedStringResource("There is no page \(number) in this notebook.", table: "Editor"))
            return
        }
        goToPage(id: pageIDs[number - 1], animated: true)
    }

    func setScrollDirection(_ direction: ScrollDirection) {
        guard direction != scrollDirection else { return }
        scrollDirection = direction
        notebook.scrollDirectionValue = direction
        markDirty(notebook, fields: ["scrollDirection"])
        do { try services.context.save() } catch { report(error) }
        layoutRevision += 1
    }

    // MARK: EditorContext

    func present(_ sheet: EditorSheet) { self.sheet = sheet }

    func showToast(_ message: LocalizedStringResource) { toast = ToastItem(message: message) }

    func setZoomScale(_ scale: CGFloat, animated: Bool) { viewport?.setZoom(scale, animated: animated) }

    func viewportDidZoom(_ scale: CGFloat) {
        guard abs(scale - zoomScale) > 0.001 else { return }
        zoomScale = scale
    }

    // MARK: Errors

    func report(_ error: Error) {
        alert = EditorAlert(message: error.localizedDescription)
    }

    func reportSaveFailure(_ error: Error) {
        saveFailure = String(localized: "Your latest writing could not be saved (\(error.localizedDescription)). Sheafnote will keep trying; the ink is still on screen.",
                             table: "Editor")
    }

    func clearSaveError() { saveFailure = nil }

    // MARK: Tools

    func inkDidChangeFromCanvas(on page: PageSession) {
        if !selection.isEmpty { selection.clear() }
    }

    func canvasEndedUsingTool() {
        guard toolState.activeToolID == .eraser, prefs.values.eraserSwitchBack else { return }
        eraserFinished()
    }

    /// "Switch back to the previous tool after erasing".
    func eraserFinished() {
        guard prefs.values.eraserSwitchBack, toolState.previousToolID != .eraser else { return }
        toolState.select(toolState.previousToolID)
    }

    var activeTool: (any EditorTool)? { host.tools.tool(toolState.activeToolID) }

    /// Signature of everything that configures the live canvases; the canvas host re-applies tools when it changes.
    var toolConfiguration: ToolConfiguration {
        ToolConfiguration(tool: toolState.activeToolID, inputMode: toolState.inputMode,
                          presetRevision: presetStore.revision, prefs: prefs.values)
    }

    private func observeTools() {
        withObservationTracking {
            _ = toolState.activeToolID
            _ = toolState.inputMode
            _ = prefs.values
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.toolsDidChange()
                self?.observeTools()
            }
        }
    }

    private func toolsDidChange() {
        let now = toolState.activeToolID
        syncInputMode()
        guard now != activeToolSeen else { return }
        host.tools.tool(activeToolSeen)?.deactivate(in: self)
        activeToolSeen = now
        host.tools.tool(now)?.activate(in: self)
        if [.pen, .highlighter, .eraser].contains(now), !selection.isEmpty { selection.clear() }
    }

    /// `ToolState.inputMode` and the persisted preference follow each other, whichever changed last.
    private func syncInputMode() {
        if toolState.inputMode != inputSeen {
            inputSeen = toolState.inputMode
            prefs.inputMode = inputSeen
        } else if prefs.inputMode != inputSeen {
            inputSeen = prefs.inputMode
            toolState.inputMode = inputSeen
        }
    }

    // MARK: Undo state

    private func observeUndo() {
        let center = NotificationCenter.default
        let names: [Notification.Name] = [.NSUndoManagerDidUndoChange, .NSUndoManagerDidRedoChange,
                                          .NSUndoManagerDidCloseUndoGroup, .NSUndoManagerCheckpoint]
        for name in names {
            let token = center.addObserver(forName: name, object: undoManager, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshUndoState() }
            }
            observers.append(token)
        }
    }

    // MARK: Sync

    private func observeServerChanges() {
        let token = NotificationCenter.default.addObserver(forName: .sheafnoteServerChangesApplied, object: nil,
                                                           queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.serverChangesApplied() }
        }
        observers.append(token)
    }

    /// iCloud changed rows in the store: bring the open pages, their elements and the page list up to date, never
    /// letting a stale in-memory copy overwrite what arrived.
    func serverChangesApplied() {
        for page in pageSessions.values {
            page.reconcileWithStore()
            page.refreshSnapshot()
            page.reloadElements()
        }
        reloadPages()
    }

    private func refreshUndoState() {
        canUndo = undoManager.canUndo
        canRedo = undoManager.canRedo
    }

    func undo() {
        selection.livePreviewTransform = .identity
        undoManager.undo()
    }

    func redo() { undoManager.redo() }
}

/// Everything the canvases need to configure PencilKit; `Equatable` so observers can detect real changes.
struct ToolConfiguration: Equatable {
    let tool: ToolID
    let inputMode: InputMode
    let presetRevision: Int
    let prefs: EditorPreferenceValues
}
