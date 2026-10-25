import Observation
import SwiftUI
import UIKit
import SheafnoteCore

/// A page's place in the content view: paper-colored with a soft shadow. It always exists, so fast scrolling shows
/// blank paper instead of a gap while the live page (with its canvas) is being prepared.
final class PageSlotView: UIView {
    init(frame: CGRect, paper: UIColor) {
        super.init(frame: frame)
        backgroundColor = paper
        layer.shadowColor = Theme.pageShadowUIColor.cgColor
        layer.shadowOpacity = 0.22
        layer.shadowRadius = 10
        layer.shadowOffset = CGSize(width: 0, height: 3)
        layer.shadowPath = UIBezierPath(rect: bounds).cgPath
        isUserInteractionEnabled = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}

/// Hosts the whole notebook in one zoomable scroll view: pages laid out vertically (continuous) or horizontally
/// (snapping page by page). Only pages near the viewport hold a live `PageContainerView` with a `PKCanvasView`.
@MainActor
final class NotebookScrollController: UIViewController, UIScrollViewDelegate, UIPencilInteractionDelegate, NotebookViewport {
    let session: NotebookSession
    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private var layout = PageLayout.empty
    private var slots: [UUID: PageSlotView] = [:]
    private var containers: [UUID: PageContainerView] = [:]
    private var fitScale: CGFloat = 1
    private var lastLayoutRevision = -1
    private var lastConfiguration: ToolConfiguration?
    private var lastViewport = CGSize.zero
    private var isRelayouting = false
    /// The page under the viewport's center when a horizontal drag began; a flick pages from here.
    private var dragStartPage: UUID?
    private let maxLivePages = 9

    /// The active fold dividing the canvas into left and right halves (iPhone Duo held like a book), in this view's
    /// coordinates. While there is one, pages show as facing spreads with the fold in the gutter.
    var fold: CGRect? {
        didSet { if fold != oldValue { relayout(keepingPosition: false) } }
    }

    init(session: NotebookSession) {
        self.session = session
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var undoManager: UndoManager? { session.undoManager }

    // MARK: Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        scrollView.frame = view.bounds
        scrollView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scrollView.delegate = self
        scrollView.backgroundColor = .clear
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.delaysContentTouches = false
        scrollView.bouncesZoom = true
        scrollView.decelerationRate = .normal
        scrollView.panGestureRecognizer.allowedTouchTypes = [UITouch.TouchType.direct, .indirectPointer].map { NSNumber(value: $0.rawValue) }
        scrollView.addSubview(contentView)
        view.addSubview(scrollView)
        view.addInteraction(UIPencilInteraction(delegate: self))
        addFingerTap(touches: 2, action: #selector(twoFingerTapped))
        addFingerTap(touches: 3, action: #selector(threeFingerTapped))
        session.viewport = self
        observeSession()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let viewport = viewportSize
        guard viewport != lastViewport else { return }
        lastViewport = viewport
        relayout(keepingPosition: true)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        session.flushAll()
    }

    // MARK: Observation

    private func observeSession() {
        withObservationTracking {
            _ = session.layoutRevision
            _ = session.toolConfiguration
            _ = session.pageSessions.values.map(\.layersRevision)
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.sessionChanged()
                self?.observeSession()
            }
        }
    }

    private func sessionChanged() {
        if session.layoutRevision != lastLayoutRevision { relayout(keepingPosition: false) }
        let configuration = session.toolConfiguration
        if configuration != lastConfiguration { applyTools(configuration) }
        containers.values.forEach { $0.refreshLayersIfNeeded() }
    }

    // MARK: Layout

    private var viewportSize: CGSize {
        let safe = view.safeAreaInsets
        return CGSize(width: max(view.bounds.width - safe.left - safe.right, 1),
                      height: max(view.bounds.height - safe.top - safe.bottom, 1))
    }

    private func relayout(keepingPosition: Bool) {
        guard isViewLoaded else { return }
        lastLayoutRevision = session.layoutRevision
        let wasAtFit = abs(scrollView.zoomScale - fitScale) < 0.01 * max(fitScale, 0.01)
        let previousOffset = scrollView.contentOffset
        let previousZoom = scrollView.zoomScale
        let directionChanged = layout.direction != session.scrollDirection

        let infos = session.pageIDs.map { (id: $0, size: session.pageSizes[$0] ?? CGSize(width: 595, height: 842)) }
        layout = PageLayoutEngine.layout(pages: infos, direction: session.scrollDirection, fold: layoutFold)
        isRelayouting = true
        reconcileSlots()
        fitScale = PageLayoutEngine.fitScale(viewport: viewportSize, layout: layout, focus: session.currentPageID)

        scrollView.minimumZoomScale = 0.01
        scrollView.maximumZoomScale = 100
        scrollView.zoomScale = 1
        contentView.frame = CGRect(origin: .zero, size: layout.contentSize)
        scrollView.contentSize = layout.contentSize
        scrollView.minimumZoomScale = fitScale
        scrollView.maximumZoomScale = max(fitScale * 8, 6)
        let target = (wasAtFit || directionChanged || previousZoom <= 0) ? fitScale : min(max(previousZoom, fitScale), scrollView.maximumZoomScale)
        scrollView.zoomScale = target
        updateInsets()
        isRelayouting = false

        if keepingPosition, !wasAtFit, !directionChanged {
            scrollView.contentOffset = clamped(previousOffset)
        } else if case .infinite = session.sizing {
            scrollView.contentOffset = clamped(previousOffset)
        } else if let current = session.currentPageID {
            scrollToPage(id: current, animated: false)
        } else {
            scrollView.contentOffset = CGPoint(x: -scrollView.contentInset.left, y: -scrollView.contentInset.top)
        }
        session.viewportDidZoom(scrollView.zoomScale)
        updateLivePages()
        updateInkZoom()
        applyTools(session.toolConfiguration)
        configurePanForInput()
    }

    /// The fold as the layout engine needs it. A fold off the viewport's center counts as wider, so the centered gutter
    /// still covers it. The infinite whiteboard has no pages to spread.
    private var layoutFold: PageLayoutEngine.Fold? {
        guard let fold, case .fixed = session.sizing else { return nil }
        let viewport = viewportSize
        let offCenter = abs(fold.midX - (view.safeAreaInsets.left + viewport.width / 2))
        return PageLayoutEngine.Fold(viewport: viewport, width: fold.width + 2 * offCenter)
    }

    private func reconcileSlots() {
        let ids = Set(layout.entries.map(\.id))
        for (id, slot) in slots where !ids.contains(id) {
            slot.removeFromSuperview()
            slots[id] = nil
        }
        for id in containers.keys where !ids.contains(id) { removeContainer(id, flush: false) }
        for entry in layout.entries {
            let paper = paperColor(for: entry.id)
            if let slot = slots[entry.id] {
                if slot.frame != entry.frame {
                    slot.frame = entry.frame
                    slot.layer.shadowPath = UIBezierPath(rect: slot.bounds).cgPath
                }
                slot.backgroundColor = paper
            } else {
                let slot = PageSlotView(frame: entry.frame, paper: paper)
                contentView.insertSubview(slot, at: 0)
                slots[entry.id] = slot
            }
            containers[entry.id]?.frame = entry.frame
        }
    }

    private func paperColor(for id: UUID) -> UIColor {
        guard let page = session.services.pages.page(id: id) else { return .white }
        let color = page.paperColorOverrideValue ?? session.notebook.paperColorValue
        return UIColor(cgColor: PaperPalette.palette(for: color).paper.cgColor)
    }

    /// Keeps content centered when it is smaller than the viewport (zoomed out, or few pages).
    private func updateInsets() {
        let safe = view.safeAreaInsets
        let viewport = viewportSize
        let content = CGSize(width: layout.contentSize.width * scrollView.zoomScale,
                             height: layout.contentSize.height * scrollView.zoomScale)
        let extraX = max(0, (viewport.width - content.width) / 2)
        let extraY = max(0, (viewport.height - content.height) / 2)
        scrollView.contentInset = UIEdgeInsets(top: safe.top + extraY, left: safe.left + extraX,
                                               bottom: safe.bottom + extraY, right: safe.right + extraX)
    }

    private func clamped(_ offset: CGPoint) -> CGPoint {
        let inset = scrollView.contentInset
        let minX = -inset.left, minY = -inset.top
        let maxX = max(minX, scrollView.contentSize.width - scrollView.bounds.width + inset.right)
        let maxY = max(minY, scrollView.contentSize.height - scrollView.bounds.height + inset.bottom)
        return CGPoint(x: min(max(offset.x, minX), maxX), y: min(max(offset.y, minY), maxY))
    }

    // MARK: Live pages

    var livePageIDs: [UUID] { layout.entries.map(\.id).filter { containers[$0] != nil } }

    var visiblePageIDs: [UUID] {
        guard isViewLoaded else { return [] }
        return layout.pages(intersecting: visibleContentRect).filter { containers[$0] != nil }
    }

    private var visibleContentRect: CGRect { scrollView.convert(scrollView.bounds, to: contentView) }

    private func updateLivePages() {
        guard !layout.entries.isEmpty else { return }
        let visible = visibleContentRect
        let reach = layout.direction == .vertical
            ? visible.insetBy(dx: 0, dy: -visible.height * 1.2)
            : visible.insetBy(dx: -visible.width * 1.2, dy: 0)
        let current = layout.currentPage(visibleRect: visible)
        var wanted = layout.pages(intersecting: reach)
        if wanted.count > maxLivePages {
            let center = CGPoint(x: visible.midX, y: visible.midY)
            wanted = Array(wanted.sorted { distance(of: $0, to: center) < distance(of: $1, to: center) }.prefix(maxLivePages))
        }
        if let current, !wanted.contains(current) { wanted.append(current) }
        let wantedSet = Set(wanted)
        for id in containers.keys where !wantedSet.contains(id) { removeContainer(id, flush: true) }
        for id in wanted where containers[id] == nil { addContainer(id) }
        if let current { session.setCurrentPage(current) }
    }

    private func distance(of id: UUID, to point: CGPoint) -> CGFloat {
        guard let frame = layout.frame(of: id) else { return .greatestFiniteMagnitude }
        return hypot(frame.midX - point.x, frame.midY - point.y)
    }

    private func addContainer(_ id: UUID) {
        guard let frame = layout.frame(of: id), let index = layout.index(of: id),
              let page = session.pageSession(for: id) else { return }
        let container = PageContainerView(page: page, session: session, number: index + 1, count: layout.entries.count)
        container.frame = frame
        contentView.addSubview(container)
        page.container = container
        containers[id] = container
        ToolConfigurator.apply(session.toolConfiguration, session: session, container: container)
        container.setInkZoom(inkZoom)
    }

    private func removeContainer(_ id: UUID, flush: Bool) {
        containers[id]?.removeFromSuperview()
        containers[id] = nil
        if flush { session.releasePage(id: id) }
    }

    /// Zoom the page canvases render ink at; below 1 the screen's own scale already oversamples.
    private var inkZoom: CGFloat { min(max(scrollView.zoomScale, 1), 4) }

    // MARK: Tools

    private func applyTools(_ configuration: ToolConfiguration) {
        lastConfiguration = configuration
        for container in containers.values {
            ToolConfigurator.apply(configuration, session: session, container: container)
        }
        configurePanForInput()
    }

    /// With fingers allowed to draw, scrolling needs two fingers; otherwise one finger scrolls (Pencil never does).
    private func configurePanForInput() {
        scrollView.panGestureRecognizer.minimumNumberOfTouches = session.toolState.inputMode == .anyInput ? 2 : 1
    }

    // MARK: NotebookViewport

    func scrollToPage(id: UUID, animated: Bool) {
        guard let frame = layout.focus(of: id) else { return }
        let z = scrollView.zoomScale
        let inset = scrollView.contentInset
        let safe = view.safeAreaInsets
        let viewport = viewportSize
        var offset = scrollView.contentOffset
        switch layout.direction {
        case .vertical:
            offset.y = z * frame.minY - inset.top + 8
            if z <= fitScale * 1.001 { offset.x = -inset.left }
        case .horizontal:
            offset.x = z * frame.midX - safe.left - viewport.width / 2
            offset.y = z <= fitScale * 1.001 ? -inset.top : offset.y
        }
        scrollView.setContentOffset(clamped(offset), animated: animated)
    }

    func setZoom(_ scale: CGFloat, animated: Bool) {
        // Same units as `PageContext.zoomScale`: 1 is one page point per screen point, `fitScale` fits the page width.
        scrollView.setZoomScale(min(max(scale, fitScale), scrollView.maximumZoomScale), animated: animated)
        if !animated { updateInkZoom() }
    }

    private func updateInkZoom() {
        let zoom = inkZoom
        containers.values.forEach { $0.setInkZoom(zoom) }
    }

    // MARK: UIScrollViewDelegate

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { contentView }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        guard !isRelayouting else { return }
        updateInsets()
        session.viewportDidZoom(scrollView.zoomScale)
    }

    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        updateInkZoom()
        updateLivePages()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard !isRelayouting else { return }
        updateLivePages()
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        dragStartPage = layout.currentPage(visibleRect: visibleContentRect)
    }

    func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint,
                                   targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        guard layout.direction == .horizontal, scrollView.zoomScale <= fitScale * 1.02 else { return }
        let z = scrollView.zoomScale
        let safe = view.safeAreaInsets
        let projectedCenter = (targetContentOffset.pointee.x + safe.left + viewportSize.width / 2) / z
        guard let id = PageLayoutEngine.snapTarget(in: layout, projectedCenterX: projectedCenter, from: dragStartPage,
                                                   velocity: velocity.x),
              let frame = layout.focus(of: id) else { return }
        targetContentOffset.pointee.x = clamped(CGPoint(x: z * frame.midX - safe.left - viewportSize.width / 2, y: 0)).x
    }

    // MARK: Finger taps

    /// Two-finger tap undoes, three-finger tap redoes. A tap fails as soon as the fingers move, so pans and pinches
    /// are unaffected, and Pencil touches are ignored.
    private func addFingerTap(touches: Int, action: Selector) {
        let tap = UITapGestureRecognizer(target: self, action: action)
        tap.numberOfTouchesRequired = touches
        tap.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        view.addGestureRecognizer(tap)
    }

    @objc private func twoFingerTapped() {
        guard session.canUndo else { return }
        session.undo()
        Haptics.light()
    }

    @objc private func threeFingerTapped() {
        guard session.canRedo else { return }
        session.redo()
        Haptics.light()
    }

    // MARK: UIPencilInteractionDelegate

    func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveTap tap: UIPencilInteraction.Tap) {
        session.handlePencil(.doubleTap)
    }

    func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveSqueeze squeeze: UIPencilInteraction.Squeeze) {
        if squeeze.phase == .ended { session.handlePencil(.squeeze) }
    }
}
