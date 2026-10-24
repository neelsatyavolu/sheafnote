import Observation
import PencilKit
import SwiftUI
import SheafnoteCore

/// One notebook's zoom window: the focus box on a page, the magnified strip image, and the writing that flows from the
/// strip back into the page's ink as ordinary undoable strokes.
@MainActor @Observable
final class ZoomWindowController {
    private static var controllers: [UUID: ZoomWindowController] = [:]

    static func controller(for editor: EditorContext) -> ZoomWindowController {
        let id = editor.notebook.id
        if let existing = controllers[id] {
            existing.editor = editor
            return existing
        }
        let created = ZoomWindowController(editor: editor)
        controllers[id] = created
        return created
    }

    static func existing(for notebookID: UUID) -> ZoomWindowController? { controllers[notebookID] }

    private(set) var model = ZoomWindowModel(pageSize: CGSize(width: 612, height: 792))
    private(set) var pageID: UUID?
    private(set) var isActive = false
    private(set) var stripImage: CGImage?
    private(set) var pendingStrokes: [[StripSample]] = []
    private(set) var liveSamples: [StripSample] = []
    private(set) var stripSize = CGSize(width: 600, height: 120)
    private(set) var errorMessage: String?
    private(set) var inkSpec: ZoomInkSpec?

    @ObservationIgnored weak var editor: (any EditorContext)?
    @ObservationIgnored private var refreshGeneration = 0
    @ObservationIgnored private var displayScale: CGFloat = 2

    private init(editor: EditorContext) { self.editor = editor }

    // MARK: Lifecycle

    func activate() {
        isActive = true
        syncToCurrentPage()
    }

    func deactivate() {
        isActive = false
        pendingStrokes = []
        liveSamples = []
    }

    /// Follows the page in view unless the user parked the box on another page.
    func syncToCurrentPage() {
        guard let page = editor?.currentPage, page.pageID != pageID else { return }
        attach(to: page)
    }

    private func attach(to page: any PageContext) {
        pageID = page.pageID
        var fresh = ZoomWindowModel(pageSize: page.pageSize, magnification: model.magnification, stripAspect: model.stripAspect,
                                    leftMargin: model.leftMargin, rightMargin: model.rightMargin)
        fresh.triggerFraction = model.triggerFraction
        fresh.autoAdvance = model.autoAdvance
        model = fresh
        refreshImage()
    }

    // MARK: Focus box

    func focus(on page: any PageContext, center: CGPoint) {
        if pageID != page.pageID { attach(to: page) }
        let size = model.focusSize
        model.moveFocus(to: CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2))
        refreshImage()
    }

    func nudge(_ direction: NudgeDirection) {
        let step = model.focusSize.height * 0.5
        model.moveFocus(by: CGSize(width: direction.dx * step * 2, height: direction.dy * step))
        refreshImage()
    }

    func newLine() {
        report(model.newLine())
        refreshImage()
    }

    func setMagnification(_ value: CGFloat) { model.setMagnification(value); refreshImage() }
    func setLeftMargin(_ value: CGFloat) { model.leftMargin = value; model.normalizeMargins() }
    func setRightMargin(_ value: CGFloat) { model.rightMargin = value; model.normalizeMargins() }
    func setAutoAdvance(_ value: Bool) { model.autoAdvance = value }
    func setTrigger(_ value: CGFloat) { model.triggerFraction = value }

    // MARK: Strip

    func stripLayoutChanged(size: CGSize, displayScale: CGFloat) {
        guard size.width > 1, size.height > 1, size != stripSize || displayScale != self.displayScale else { return }
        stripSize = size
        self.displayScale = displayScale
        model.setStripAspect(size.width / size.height)
        refreshImage()
    }

    func strokeBegan(_ samples: [StripSample]) {
        if let editor { inkSpec = ZoomInkSpec.current(for: editor) }
        liveSamples = samples
    }

    func strokeMoved(_ samples: [StripSample]) { liveSamples.append(contentsOf: samples) }

    func strokeCancelled() { liveSamples = [] }

    func strokeEnded(_ samples: [StripSample]) {
        liveSamples.append(contentsOf: samples)
        let written = liveSamples
        liveSamples = []
        guard let last = written.last else { return }
        guard commit(written) else { return }
        pendingStrokes.append(written)
        if model.shouldAdvance(afterPenAtStrip: last.location, stripSize: stripSize) {
            let lastPageX = model.pageLocation(forStrip: last.location, stripSize: stripSize).x
            report(model.advance(keepingPageX: lastPageX))
            pendingStrokes = []
        }
        refreshImage()
    }

    // MARK: Writing through to the page

    private func commit(_ samples: [StripSample]) -> Bool {
        guard let editor, let pageID else { return false }
        let spec = inkSpec ?? ZoomInkSpec.current(for: editor)
        guard let stroke = ZoomStrokeBuilder.build(samples: samples, model: model, stripSize: stripSize, spec: spec) else {
            return false
        }
        guard let page = resolvePage(pageID, in: editor) else {
            editor.showToast(LocalizedStringResource("That page isn't open. Scroll to it and try again.", table: "Present"))
            return false
        }
        page.ink.edit(LocalizedStringResource("Write in Zoom Window", table: "Present")) { $0.append(stroke) }
        return true
    }

    private func resolvePage(_ id: UUID, in editor: EditorContext) -> (any PageContext)? {
        let candidates = [editor.currentPage].compactMap { $0 } + editor.visiblePages
        return candidates.first { $0.pageID == id }
    }

    private func report(_ result: ZoomWindowModel.AdvanceResult) {
        if result == .endOfPage {
            editor?.showToast(LocalizedStringResource("End of the page", table: "Present"))
        }
    }

    // MARK: Strip image

    /// Re-renders the magnified region. Stale renders are dropped; a failure is shown, never swallowed.
    func refreshImage() {
        guard let editor, let pageID else { return }
        refreshGeneration += 1
        let generation = refreshGeneration
        let rect = model.focusRect
        let scale = max(1, stripSize.width * displayScale / max(rect.width, 1))
        Task { [weak self] in
            do {
                let image = try await editor.services.pageRenderer.renderImage(pageID: pageID, rect: rect, scale: scale, options: .screen)
                self?.finishRefresh(generation: generation, image: image, error: nil)
            } catch {
                self?.finishRefresh(generation: generation, image: nil, error: error)
            }
        }
    }

    private func finishRefresh(generation: Int, image: CGImage?, error: Error?) {
        guard generation == refreshGeneration else { return }
        if let image {
            stripImage = image
            errorMessage = nil
        } else if let error {
            errorMessage = error.localizedDescription
        }
        pendingStrokes = []
    }
}

enum NudgeDirection {
    case left, right, up, down

    var dx: CGFloat { self == .left ? -1 : self == .right ? 1 : 0 }
    var dy: CGFloat { self == .up ? -1 : self == .down ? 1 : 0 }
}
