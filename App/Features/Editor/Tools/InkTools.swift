import SwiftUI
import SheafnoteCore

/// Extra controls other features may add to a tool's options row (for example the highlighter's "draw straight line"
/// switch from the ink-tools unit). Register at module registration time; the editor appends them to the row.
@MainActor
enum EditorOptionsAccessories {
    private static var registered: [ToolID: [@MainActor (EditorContext) -> AnyView]] = [:]

    static func register(for tool: ToolID, _ make: @escaping @MainActor (EditorContext) -> AnyView) {
        registered[tool, default: []].append(make)
    }

    static func views(for tool: ToolID, editor: EditorContext) -> [AnyView] {
        (registered[tool] ?? []).map { $0(editor) }
    }
}

/// Shared shape of the three built-in tools (pen, highlighter, eraser). They configure PencilKit; the canvas keeps the touches.
@MainActor
class BuiltInInkTool: EditorTool {
    let id: ToolID
    let title: LocalizedStringResource
    let symbolName: String
    let placement: ToolPlacement
    let supportedKinds: Set<NotebookKind> = [.paged, .whiteboard]
    let inputPolicy = ToolInputPolicy.canvasHandlesInput

    init(id: ToolID, title: LocalizedStringResource, symbolName: String, order: Int) {
        self.id = id
        self.title = title
        self.symbolName = symbolName
        self.placement = .primary(order: order)
    }

    func makeOptionsView(in editor: EditorContext) -> AnyView {
        guard let session = editor as? NotebookSession else { return AnyView(EmptyView()) }
        return AnyView(InkOptionsRow(toolID: id, session: session))
    }
}

@MainActor
final class PenTool: BuiltInInkTool {
    init() {
        super.init(id: .pen, title: LocalizedStringResource("Pen", table: "Editor"), symbolName: "pencil.tip", order: 10)
    }
}

@MainActor
final class HighlighterTool: BuiltInInkTool {
    init() {
        super.init(id: .highlighter, title: LocalizedStringResource("Highlighter", table: "Editor"),
                   symbolName: "highlighter", order: 30)
    }
}

@MainActor
final class EraserTool: BuiltInInkTool {
    init() {
        super.init(id: .eraser, title: LocalizedStringResource("Eraser", table: "Editor"), symbolName: "eraser", order: 20)
    }

    override func makeOptionsView(in editor: EditorContext) -> AnyView {
        guard let session = editor as? NotebookSession else { return AnyView(EmptyView()) }
        return AnyView(EraserOptionsRow(session: session))
    }
}
