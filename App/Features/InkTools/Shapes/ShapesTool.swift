import PencilKit
import SwiftUI
import SheafnoteCore

/// The shapes tool: draw a shape, or let the tool recognise one, and it becomes an editable shape element.
/// A gesture that is not a shape stays as ordinary ink in the outline colour, so nothing drawn is lost.
@MainActor
final class ShapesTool: EditorTool {
    let id = ToolID.shapes
    let title = LocalizedStringResource("Shapes", table: "InkTools")
    let symbolName = "square.on.circle"
    let placement = ToolPlacement.primary(order: 40)
    let supportedKinds: Set<NotebookKind> = [.paged, .whiteboard]

    private let settings: InkToolsSettings
    private weak var editor: (any EditorContext)?
    private let pruner = SelectionPruner()

    init(settings: InkToolsSettings) { self.settings = settings }

    var inputPolicy: ToolInputPolicy {
        editor?.toolState.inputMode == .pencilOnly ? .overlayCapturesPencil : .overlayCapturesAll
    }

    func activate(in editor: EditorContext) {
        self.editor = editor
        pruner.start(editor: editor)
    }

    func deactivate(in editor: EditorContext) { pruner.stop() }

    func makeOptionsView(in editor: EditorContext) -> AnyView {
        AnyView(ShapesOptionsRow(settings: settings))
    }

    func makeOverlay(for page: PageContext, in editor: EditorContext) -> AnyView? {
        AnyView(ShapesOverlay(tool: self, page: page, editor: editor, settings: settings))
    }

    /// Turns a finished gesture (page coordinates) into a shape element, or into plain ink when it is no shape.
    func commit(_ path: [CGPoint], page: any PageContext, editor: EditorContext) {
        let options = settings.shape
        let figure = Self.figure(for: path, mode: options.mode)
        do {
            if let figure {
                try addShape(figure, options: options, page: page, editor: editor)
            } else if options.mode == .auto, let stroke = FreehandStroke.make(points: path, colorHex: options.strokeHex, width: options.lineWidth) {
                page.ink.edit(LocalizedStringResource("Draw", table: "InkTools")) { $0.append(stroke) }
            }
        } catch {
            InkToolsErrors.report(error, editor: editor)
        }
    }

    static func figure(for path: [CGPoint], mode: ShapeMode) -> ShapeFigure? {
        if let kind = mode.kind { return ShapeBuilder.figure(kind: kind, path: path) }
        return ShapeRecognizer.recognize(path)
    }

    private func addShape(_ figure: ShapeFigure, options: ShapeToolSettings, page: any PageContext, editor: EditorContext) throws {
        let top = page.elements.all.map(\.zIndex).max() ?? 0
        let element = ShapeElementGeometry.element(for: figure, pageID: page.pageID, zIndex: top + 1, strokeHex: options.strokeHex,
                                                   fillHex: options.fillHex, lineWidth: options.lineWidth)
        let stored = try page.elements.add(element, undoName: LocalizedStringResource("Add Shape", table: "InkTools"))
        editor.selection.select(pageID: page.pageID, strokeIDs: [], elementIDs: [stored.id],
                                bounds: ShapeHitTester(element: stored).bounds)
    }
}

/// Reports a failure to the user: through the editor's own error presentation when there is one, else a toast.
@MainActor
enum InkToolsErrors {
    static func report(_ error: Error, editor: EditorContext) {
        if let session = editor as? NotebookSession {
            session.report(error)
        } else {
            editor.showToast(LocalizedStringResource(stringLiteral: error.localizedDescription))
        }
    }
}
