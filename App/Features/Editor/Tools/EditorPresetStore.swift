import Foundation
import Observation
import PencilKit
import SheafnoteCore

/// Width choices (three presets plus the selected one) for a tool. Stored next to the color presets.
struct WidthPresets: Codable, Equatable, Sendable {
    var values: [Double]
    var selectedIndex: Int

    var selected: Double { values.indices.contains(selectedIndex) ? values[selectedIndex] : (values.first ?? 3) }
}

/// `ToolPresetStore` over `AppSettingsStore`. Color presets sync under "toolPresets.<id>"; width presets under
/// "toolWidths.<id>"; the selected color preset is device-local.
@MainActor @Observable
final class EditorPresetStore: ToolPresetStore {
    private let settings: AppSettingsStore
    /// Bumped on every change so observers (canvas configuration, options rows) refresh.
    private(set) var revision = 0
    private(set) var lastError: String?

    init(settings: AppSettingsStore) { self.settings = settings }

    // MARK: ToolPresetStore

    func presets(for tool: ToolID) -> [ToolPreset] {
        if let stored = settings.synced("toolPresets.\(tool.rawValue)", as: [ToolPreset].self), !stored.isEmpty { return stored }
        return Self.defaultPresets(for: tool)
    }

    func setPresets(_ presets: [ToolPreset], for tool: ToolID) {
        persist(presets, key: "toolPresets.\(tool.rawValue)")
    }

    func selectedPresetID(for tool: ToolID) -> UUID? {
        let all = presets(for: tool)
        if let id = settings.local("toolPresetSelected.\(tool.rawValue)", as: UUID.self), all.contains(where: { $0.id == id }) {
            return id
        }
        return all.first?.id
    }

    func selectPreset(_ id: UUID, for tool: ToolID) {
        settings.setLocal(id, for: "toolPresetSelected.\(tool.rawValue)")
        revision += 1
    }

    // MARK: Widths and ink

    func widths(for tool: ToolID) -> WidthPresets {
        if let stored = settings.synced("toolWidths.\(tool.rawValue)", as: WidthPresets.self), !stored.values.isEmpty { return stored }
        return Self.defaultWidths(for: tool)
    }

    func setWidths(_ widths: WidthPresets, for tool: ToolID) {
        persist(widths, key: "toolWidths.\(tool.rawValue)")
    }

    func selectWidth(index: Int, for tool: ToolID) {
        var w = widths(for: tool)
        guard w.values.indices.contains(index) else { return }
        w.selectedIndex = index
        setWidths(w, for: tool)
    }

    func selectedPreset(for tool: ToolID) -> ToolPreset? {
        let all = presets(for: tool)
        return all.first { $0.id == selectedPresetID(for: tool) } ?? all.first
    }

    /// The ink kind is a tool-level choice: it is written to every preset of the tool.
    func setInkKind(_ kind: InkKind, for tool: ToolID) {
        var all = presets(for: tool)
        for i in all.indices { all[i].inkKind = kind }
        setPresets(all, for: tool)
    }

    func inkKind(for tool: ToolID) -> InkKind {
        selectedPreset(for: tool)?.inkKind ?? Self.defaultInk(for: tool)
    }

    /// Colour presets are capped so the row stays usable; the oldest non-selected one is dropped.
    func addColor(hex: String, for tool: ToolID, maxCount: Int = 8) {
        var all = presets(for: tool)
        let template = selectedPreset(for: tool)
        let new = ToolPreset(id: UUID(), colorHex: hex, width: widths(for: tool).selected, inkKind: template?.inkKind ?? Self.defaultInk(for: tool))
        all.append(new)
        if all.count > maxCount, let drop = all.firstIndex(where: { $0.id != new.id && $0.id != template?.id }) { all.remove(at: drop) }
        setPresets(all, for: tool)
        selectPreset(new.id, for: tool)
    }

    func updateSelectedColor(hex: String, for tool: ToolID) {
        guard let id = selectedPresetID(for: tool) else { return }
        var all = presets(for: tool)
        guard let i = all.firstIndex(where: { $0.id == id }) else { return }
        all[i].colorHex = hex
        setPresets(all, for: tool)
    }

    // MARK: Defaults

    static func defaultInk(for tool: ToolID) -> InkKind { tool == .highlighter ? .marker : .pen }

    static func defaultPresets(for tool: ToolID) -> [ToolPreset] {
        let ink = defaultInk(for: tool)
        let colors: [String]
        switch tool {
        case .highlighter: colors = ["#FFE066", "#8CE99A", "#FFA8D1", "#74C0FC"]
        default: colors = ["#1B1B1F", "#2F5BEA", "#D6336C", "#2B8A3E"]
        }
        let width = defaultWidths(for: tool).selected
        return colors.enumerated().map { i, hex in
            ToolPreset(id: stableID(tool: tool, index: i), colorHex: hex, width: width, inkKind: ink)
        }
    }

    static func defaultWidths(for tool: ToolID) -> WidthPresets {
        switch tool {
        case .highlighter: WidthPresets(values: [10, 18, 28], selectedIndex: 1)
        case .eraser: WidthPresets(values: [10, 24, 48], selectedIndex: 1)
        default: WidthPresets(values: [1.5, 3, 6], selectedIndex: 1)
        }
    }

    /// Defaults get fixed ids so "selected preset" survives relaunch before the user edits anything.
    private static func stableID(tool: ToolID, index: Int) -> UUID {
        var bytes = [UInt8](repeating: 0, count: 16)
        for (i, b) in tool.rawValue.utf8.prefix(10).enumerated() { bytes[i] = b }
        bytes[15] = UInt8(index)
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    private func persist<T: Encodable>(_ value: T, key: String) {
        do {
            try settings.setSynced(value, for: key)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        revision += 1
    }
}

extension InkKind {
    var pkType: PKInk.InkType {
        switch self {
        case .pen: .pen
        case .fountainPen: .fountainPen
        case .monoline: .monoline
        case .pencil: .pencil
        case .crayon: .crayon
        case .watercolor: .watercolor
        case .marker: .marker
        }
    }

    var title: LocalizedStringResource {
        switch self {
        case .pen: LocalizedStringResource("Pen", table: "Editor")
        case .fountainPen: LocalizedStringResource("Fountain Pen", table: "Editor")
        case .monoline: LocalizedStringResource("Monoline", table: "Editor")
        case .pencil: LocalizedStringResource("Pencil", table: "Editor")
        case .crayon: LocalizedStringResource("Crayon", table: "Editor")
        case .watercolor: LocalizedStringResource("Watercolor", table: "Editor")
        case .marker: LocalizedStringResource("Marker", table: "Editor")
        }
    }

    var symbolName: String {
        switch self {
        case .pen: "pencil.tip"
        case .fountainPen: "highlighter"
        case .monoline: "pencil.line"
        case .pencil: "pencil"
        case .crayon: "paintbrush.pointed"
        case .watercolor: "paintbrush"
        case .marker: "paintbrush.pointed.fill"
        }
    }

    /// Inks offered by the pen tool (the marker belongs to the highlighter).
    static let penChoices: [InkKind] = [.pen, .fountainPen, .monoline, .pencil, .crayon, .watercolor]
}

/// Builds the PencilKit tool for the current preset, width and ink, clamping width to what the ink supports.
enum InkToolFactory {
    static func pencilKitTool(kind: InkKind, colorHex: String, width: Double) -> PKInkingTool {
        let type = kind.pkType
        let range = type.validWidthRange
        let clamped = min(max(CGFloat(width), range.lowerBound), range.upperBound)
        return PKInkingTool(type, color: UIColor(hex: colorHex), width: clamped)
    }
}
