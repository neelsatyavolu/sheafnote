import Observation
import SwiftUI
import SheafnoteCore

struct ToolID: Hashable, Sendable, ExpressibleByStringLiteral, RawRepresentable {
    let rawValue: String
    init(rawValue: String) { self.rawValue = rawValue }
    init(stringLiteral value: String) { self.rawValue = value }

    static let pen: ToolID = "pen", highlighter: ToolID = "highlighter", eraser: ToolID = "eraser",
               lasso: ToolID = "lasso", shapes: ToolID = "shapes", element: ToolID = "element",
               text: ToolID = "text", laser: ToolID = "laser", tape: ToolID = "tape",
               zoomWindow: ToolID = "zoomWindow"
}

/// Primary tool row vs the "more" menu.
enum ToolPlacement: Sendable {
    case primary(order: Int)
    case more(order: Int)

    var order: Int {
        switch self {
        case .primary(let o), .more(let o): o
        }
    }
}

enum ToolInputPolicy: Sendable {
    case canvasHandlesInput          // PencilKit canvas gets touches; tool only configures it
    case overlayCapturesPencil       // overlay gets Pencil touches, fingers scroll/zoom
    case overlayCapturesAll          // overlay gets every touch (lasso with finger, text, laser)
}

enum PencilAction: Sendable { case doubleTap, squeeze }

@MainActor
protocol EditorTool: AnyObject {
    var id: ToolID { get }
    var title: LocalizedStringResource { get }        // also the VoiceOver label
    var symbolName: String { get }                    // SF Symbol
    var placement: ToolPlacement { get }
    var supportedKinds: Set<NotebookKind> { get }
    var inputPolicy: ToolInputPolicy { get }
    func activate(in editor: EditorContext)
    func deactivate(in editor: EditorContext)
    /// The slim second row under the tool row (presets, options). Return an `AnyView(EmptyView())` if none.
    func makeOptionsView(in editor: EditorContext) -> AnyView
    /// Transient overlay drawn above the page (lasso path, laser trail, shape preview). Page coordinates, origin top-left, points.
    func makeOverlay(for page: PageContext, in editor: EditorContext) -> AnyView?
    /// Pencil double-tap / squeeze: return true if the tool consumed the event.
    func handlePencilAction(_ action: PencilAction, in editor: EditorContext) -> Bool
}

extension EditorTool {
    func makeOverlay(for page: PageContext, in editor: EditorContext) -> AnyView? { nil }
    func handlePencilAction(_ action: PencilAction, in editor: EditorContext) -> Bool { false }
    func activate(in editor: EditorContext) {}
    func deactivate(in editor: EditorContext) {}
}

@MainActor
final class ToolRegistry {
    private var byID: [ToolID: any EditorTool] = [:]

    /// Duplicate ids trap in debug; the last registration wins in release.
    func register(_ tool: any EditorTool) {
        assert(byID[tool.id] == nil, "Duplicate tool id \(tool.id.rawValue)")
        byID[tool.id] = tool
    }

    func tools(for kind: NotebookKind) -> [any EditorTool] {
        byID.values.filter { $0.supportedKinds.contains(kind) }.sorted {
            $0.placement.order == $1.placement.order ? $0.id.rawValue < $1.id.rawValue : $0.placement.order < $1.placement.order
        }
    }

    func tool(_ id: ToolID) -> (any EditorTool)? { byID[id] }
}

enum InputMode: String, Sendable { case pencilOnly, anyInput }

@MainActor @Observable
final class ToolState {
    var activeToolID: ToolID
    var previousToolID: ToolID                  // used by "switch back after erasing" and Pencil double-tap
    var inputMode: InputMode                    // draw with finger or Pencil only

    init(activeToolID: ToolID = .pen, inputMode: InputMode = .anyInput) {
        self.activeToolID = activeToolID
        self.previousToolID = activeToolID
        self.inputMode = inputMode
    }

    func select(_ id: ToolID) {
        guard id != activeToolID else { return }
        previousToolID = activeToolID
        activeToolID = id
    }
}

enum InkKind: String, Codable, CaseIterable, Sendable { case pen, fountainPen, monoline, pencil, crayon, watercolor, marker }

struct ToolPreset: Codable, Hashable, Sendable, Identifiable {
    var id: UUID
    var colorHex: String
    var width: Double
    var inkKind: InkKind?          // nil for non-ink tools
}

@MainActor
protocol ToolPresetStore {
    func presets(for tool: ToolID) -> [ToolPreset]
    /// Persisted via `AppSettingsStore` (synced key "toolPresets.<id>").
    func setPresets(_ presets: [ToolPreset], for tool: ToolID)
    func selectedPresetID(for tool: ToolID) -> UUID?
    func selectPreset(_ id: UUID, for tool: ToolID)
}
