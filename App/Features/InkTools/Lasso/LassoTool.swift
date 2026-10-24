import SwiftUI
import SheafnoteCore

/// The lasso: draw a loop around ink, shapes, text and images to select them, or tap one item. What happens to the
/// selection (move, resize, rotate, copy, recolor, convert to text, ...) is the editor's handles plus the selection
/// actions this unit registers.
@MainActor
final class LassoTool: EditorTool {
    let id = ToolID.lasso
    let title = LocalizedStringResource("Lasso", table: "InkTools")
    let symbolName = "lasso"
    let placement = ToolPlacement.primary(order: 50)
    let supportedKinds: Set<NotebookKind> = [.paged, .whiteboard]

    private let selector: LassoSelector
    private let settings: InkToolsSettings
    private let clipboard: ClipboardService
    private weak var editor: (any EditorContext)?
    private let pruner = SelectionPruner()

    init(host: FeatureHost, settings: InkToolsSettings, clipboard: ClipboardService) {
        self.selector = LassoSelector(host: host)
        self.settings = settings
        self.clipboard = clipboard
    }

    var inputPolicy: ToolInputPolicy {
        editor?.toolState.inputMode == .pencilOnly ? .overlayCapturesPencil : .overlayCapturesAll
    }

    func activate(in editor: EditorContext) {
        self.editor = editor
        pruner.start(editor: editor)
    }

    func deactivate(in editor: EditorContext) {
        pruner.stop()
        editor.selection.clear()
    }

    func makeOptionsView(in editor: EditorContext) -> AnyView {
        AnyView(LassoOptionsRow(settings: settings, editor: editor, clipboard: clipboard, tool: self))
    }

    func makeOverlay(for page: PageContext, in editor: EditorContext) -> AnyView? {
        AnyView(LassoOverlay(tool: self, page: page, editor: editor))
    }

    // MARK: Selecting

    /// A finished drag in page coordinates: a loop selects what it encloses, a tap picks one item or clears.
    func finish(_ drag: [CGPoint], page: any PageContext, editor: EditorContext) {
        let filters = settings.lassoFilters
        if LassoGeometry.isTap(drag) {
            let pick = drag.first.flatMap { selector.pick(at: $0, on: page, filters: filters) }
            apply(pick, page: page, editor: editor)
        } else if let polygon = LassoGeometry.closedPolygon(from: drag) {
            let pick = selector.pick(inside: polygon, on: page, filters: filters)
            apply(pick, page: page, editor: editor)
            if pick == nil { editor.showToast(LocalizedStringResource("Nothing selected", table: "InkTools")) }
        } else {
            editor.selection.clear()
        }
    }

    func selectAll(page: any PageContext, editor: EditorContext) {
        let pick = selector.pickAll(on: page, filters: settings.lassoFilters)
        apply(pick, page: page, editor: editor)
        if pick == nil { editor.showToast(LocalizedStringResource("Nothing to select on this page", table: "InkTools")) }
    }

    private func apply(_ pick: LassoSelector.Pick?, page: any PageContext, editor: EditorContext) {
        guard let pick else { return editor.selection.clear() }
        editor.selection.select(pageID: page.pageID, strokeIDs: pick.strokeIDs, elementIDs: pick.elementIDs,
                                bounds: pick.bounds.insetBy(dx: -3, dy: -3))
    }
}
