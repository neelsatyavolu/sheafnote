import PencilKit
import SwiftUI
import SheafnoteCore

@MainActor
protocol EditorContext: AnyObject {
    var notebook: Notebook { get }
    var services: AppServices { get }
    var toolState: ToolState { get }
    var presets: any ToolPresetStore { get }
    var selection: SelectionModel { get }
    var selectionTransformer: any SelectionTransforming { get }
    var currentPage: (any PageContext)? { get }
    var visiblePages: [any PageContext] { get }
    /// One per notebook; undo/redo covers ink, elements and page operations.
    var undoManager: UndoManager { get }
    func goToPage(id: UUID, animated: Bool)
    /// System sheet/popover host.
    func present(_ sheet: EditorSheet)
    func showToast(_ message: LocalizedStringResource)
    func setZoomScale(_ scale: CGFloat, animated: Bool)
}

struct EditorSheet: Identifiable {
    let id = UUID()
    let content: () -> AnyView
    var detents: Set<PresentationDetent>

    init(detents: Set<PresentationDetent> = [.medium, .large], content: @escaping () -> AnyView) {
        self.detents = detents
        self.content = content
    }
}

struct IdentifiedStroke: Identifiable {
    var id: StrokeID
    var stroke: PKStroke
}

@MainActor
protocol PageContext: AnyObject {
    var notebookID: UUID { get }
    var pageID: UUID { get }
    /// Points. For infinite pages this is the current canvas size.
    var pageSize: CGSize { get }
    var zoomScale: CGFloat { get }
    var ink: any PageInkAccess { get }
    var elements: any PageElementStore { get }
    var undoManager: UndoManager { get }
    /// For popovers/menus.
    func pageToScreen(_ rect: CGRect) -> CGRect
    func screenToPage(_ point: CGPoint) -> CGPoint
}

@MainActor
protocol PageInkAccess: AnyObject {
    var strokes: [IdentifiedStroke] { get }
    /// One undoable edit; ids are recomputed (StrokeIdentity) afterwards, the page is marked dirty and saved.
    func edit(_ name: LocalizedStringResource, _ body: (inout [PKStroke]) -> Void)
    /// Lasso helper, page coordinates.
    func strokes(intersecting polygon: [CGPoint]) -> [IdentifiedStroke]
    /// Selection screenshot, flashcards.
    func render(strokeIDs: Set<StrokeID>, scale: CGFloat) -> UIImage?
    var lastInkTouchDate: Date? { get }
}

@MainActor
protocol PageElementStore: AnyObject {
    /// Value copies, z-ordered.
    var all: [ElementValue] { get }
    @discardableResult func add(_ element: ElementValue, undoName: LocalizedStringResource) throws -> ElementValue
    func update(id: UUID, undoName: LocalizedStringResource, _ mutate: (inout ElementValue) -> Void) throws
    /// Soft delete.
    func remove(ids: Set<UUID>, undoName: LocalizedStringResource) throws
}
