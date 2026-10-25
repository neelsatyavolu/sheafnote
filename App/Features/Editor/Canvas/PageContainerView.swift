import PencilKit
import SwiftUI
import UIKit
import SheafnoteCore

/// One live page: the registered layers stacked bottom to top (paper, template, background, elements below the ink,
/// the PencilKit canvas, elements above the ink), then the tool overlay and the selection overlay.
/// Its bounds are the page size in points; zooming is done by the enclosing scroll view.
@MainActor
final class PageContainerView: UIView {
    let page: PageSession
    private unowned let session: NotebookSession
    private let number: Int
    private let count: Int
    private var layerViews: [UIView] = []
    private var builtRevision = -1
    private let toolOverlay: ToolOverlayView
    private let selectionOverlay: SelectionOverlayView
    private let forwarder = InkTouchForwarder(target: nil, action: nil)
    let markerEraser = MarkerEraseRecognizer(target: nil, action: nil)
    private var eraseBase: PKDrawing?

    init(page: PageSession, session: NotebookSession, number: Int, count: Int) {
        self.page = page
        self.session = session
        self.number = number
        self.count = count
        toolOverlay = ToolOverlayView(page: page, session: session)
        selectionOverlay = SelectionOverlayView(page: page, session: session)
        super.init(frame: CGRect(origin: .zero, size: page.pageSize))
        backgroundColor = .clear
        clipsToBounds = true
        rebuildLayers()
        installRecognizers()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: Layers

    func refreshLayersIfNeeded() {
        guard builtRevision != page.layersRevision else { return }
        rebuildLayers()
    }

    private func rebuildLayers() {
        builtRevision = page.layersRevision
        layerViews.forEach { $0.removeFromSuperview() }
        toolOverlay.removeFromSuperview()
        selectionOverlay.removeFromSuperview()
        bounds = CGRect(origin: .zero, size: page.pageSize)
        layerViews = session.host.layers.providers(for: page.snapshot).map { $0.makeLayerView(for: page) }
        for view in layerViews {
            view.frame = bounds
            addSubview(view)
        }
        toolOverlay.frame = bounds
        selectionOverlay.frame = bounds
        addSubview(toolOverlay)
        addSubview(selectionOverlay)
        layoutCanvas()
        updateAccessibility()
    }

    func updateAccessibility() {
        guard let canvas = page.canvas else { return }
        canvas.isAccessibilityElement = true
        canvas.accessibilityIdentifier = "editor.page.\(number)"
        canvas.accessibilityLabel = String(localized: "Page \(number) of \(count), writing area", table: "Editor")
        let strokes = page.drawing.strokes.count
        canvas.accessibilityValue = strokes == 1 ? String(localized: "1 stroke", table: "Editor")
                                                 : String(localized: "\(strokes) strokes", table: "Editor")
        canvas.accessibilityTraits = .allowsDirectInteraction
    }

    // MARK: Raster scale

    private var inkZoom: CGFloat = 1

    /// PencilKit ignores the scale of an enclosing zoom, so its tiles get stretched and look blurry. Instead the canvas
    /// zooms itself by `zoom` and is shrunk back by the same factor: page coordinates are unchanged, pixels are 1:1.
    func setInkZoom(_ zoom: CGFloat) {
        guard abs(inkZoom - zoom) > 0.01 else { return }
        inkZoom = zoom
        layoutCanvas()
    }

    private func layoutCanvas() {
        guard let canvas = page.canvas else { return }
        let zoom = inkZoom
        canvas.transform = .identity
        canvas.zoomScale = 1
        canvas.minimumZoomScale = zoom
        canvas.maximumZoomScale = zoom
        canvas.pinchGestureRecognizer?.isEnabled = false
        canvas.bounds = CGRect(origin: .zero, size: CGSize(width: bounds.width * zoom, height: bounds.height * zoom))
        canvas.contentSize = bounds.size
        canvas.zoomScale = zoom
        canvas.contentOffset = .zero
        canvas.transform = CGAffineTransform(scaleX: 1 / zoom, y: 1 / zoom)
        canvas.center = CGPoint(x: bounds.midX, y: bounds.midY)
    }

    // MARK: Touch routing

    private func installRecognizers() {
        forwarder.isWanted = { [unowned self] in
            !session.host.touchObservers.observers(for: session.toolState.activeToolID).isEmpty
        }
        forwarder.onBegan = { [unowned self] sample in
            for o in observers { o.strokeBegan(sample, page: page, editor: session) }
        }
        forwarder.onMoved = { [unowned self] samples in
            for o in observers { o.strokeMoved(samples, page: page, editor: session) }
        }
        forwarder.onEnded = { [unowned self] sample in
            for o in observers { o.strokeEnded(sample, page: page, editor: session) }
        }
        forwarder.onCancelled = { [unowned self] in
            for o in observers { o.strokeCancelled(page: page, editor: session) }
        }
        addGestureRecognizer(forwarder)

        markerEraser.onBegan = { [unowned self] in eraseBase = page.drawing }
        markerEraser.onSamples = { [unowned self] points in eraseMarkers(near: points) }
        markerEraser.onEnded = { [unowned self] in finishErase() }
        markerEraser.isEnabled = false
        addGestureRecognizer(markerEraser)
    }

    private var observers: [any InkTouchObserver] {
        session.host.touchObservers.observers(for: session.toolState.activeToolID)
    }

    private func eraseMarkers(near points: [CGPoint]) {
        guard page.isEditable else { return }
        let radius = session.presetStore.widths(for: .eraser).selected / 2
        let hits = MarkerEraser.markerStrokeIndices(in: page.drawing, near: points, radius: radius)
        guard !hits.isEmpty else { return }
        page.setDrawingTransient(MarkerEraser.removing(hits, from: page.drawing))
    }

    private func finishErase() {
        defer { eraseBase = nil }
        guard let base = eraseBase else { return }
        if base.strokes.count != page.drawing.strokes.count {
            page.registerDrawingUndo(old: base, name: "Erase")
        }
        session.eraserFinished()
    }

    /// Input types that may draw (and feed observers) for the current input mode.
    func setAllowedInput(_ mode: InputMode) {
        let types: [UITouch.TouchType] = mode == .pencilOnly ? [.pencil] : [.direct, .pencil]
        let numbers = types.map { NSNumber(value: $0.rawValue) }
        forwarder.allowedTouchTypes = numbers
        markerEraser.allowedTouchTypes = numbers
    }
}
