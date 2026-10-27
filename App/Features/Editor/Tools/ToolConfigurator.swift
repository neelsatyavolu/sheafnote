import PencilKit
import UIKit
import SheafnoteCore

/// Applies the active tool, the selected preset and the input mode to a live page canvas.
@MainActor
enum ToolConfigurator {
    static func apply(_ config: ToolConfiguration, session: NotebookSession, container: PageContainerView) {
        let page = container.page
        guard let canvas = page.canvas else { return }
        canvas.drawingPolicy = config.inputMode == .pencilOnly ? .pencilOnly : .anyInput
        container.setAllowedInput(config.inputMode)

        var canvasInteractive = page.isEditable
        var customEraser = false
        switch config.tool {
        case .pen, .highlighter:
            canvas.tool = inkingTool(for: config.tool, store: session.presetStore)
        case .eraser:
            if config.prefs.eraserHighlighterOnly {
                canvasInteractive = false
                customEraser = true
            } else {
                canvas.tool = eraserTool(mode: config.prefs.eraserMode, store: session.presetStore)
            }
        default:
            let policy = session.host.tools.tool(config.tool)?.inputPolicy
            if policy == .canvasHandlesInput || policy == nil {
                canvas.tool = inkingTool(for: .pen, store: session.presetStore)
            } else {
                canvasInteractive = false
            }
        }
        canvas.isUserInteractionEnabled = canvasInteractive
        container.markerEraser.isEnabled = customEraser && page.isEditable
    }

    static func inkingTool(for tool: ToolID, store: EditorPresetStore) -> PKInkingTool {
        var kind = store.inkKind(for: tool)
        if tool == .pen, kind == .marker { kind = .pen }
        if tool == .highlighter { kind = .marker }
        let color = store.selectedPreset(for: tool)?.colorHex ?? EditorPresetStore.defaultPresets(for: tool)[0].colorHex
        return InkToolFactory.pencilKitTool(kind: kind, colorHex: color, width: store.widths(for: tool).selected)
    }

    static func eraserTool(mode: EraserMode, store: EditorPresetStore) -> PKEraserTool {
        let type: PKEraserTool.EraserType = switch mode {
        case .precision: .fixedWidthBitmap
        case .standard: .bitmap
        case .stroke: .vector
        }
        let range = type.validWidthRange
        let width = min(max(CGFloat(store.widths(for: .eraser).selected), range.lowerBound), range.upperBound)
        return PKEraserTool(type, width: width)
    }
}
