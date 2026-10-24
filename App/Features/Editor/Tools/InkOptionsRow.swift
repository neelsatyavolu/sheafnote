import PencilKit
import SwiftUI
import SheafnoteCore

/// The slim row under the tool row for pen and highlighter: ink type, color presets, three width presets and "+".
/// Tapping the selected color opens its editor (color, width).
struct InkOptionsRow: View {
    let toolID: ToolID
    let session: NotebookSession
    @State private var showEditor = false
    @State private var showAdd = false
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var metrics: OptionsMetrics { OptionsMetrics(compact: sizeClass == .compact) }
    private var store: EditorPresetStore { session.presetStore }

    var body: some View {
        let _ = store.revision
        HStack(spacing: metrics.spacing) {
            if toolID == .pen { inkMenu }
            OptionsDivider()
            ForEach(store.presets(for: toolID)) { swatch($0) }
            addButton
            OptionsDivider()
            WidthDots(toolID: toolID, store: store)
            ForEach(Array(EditorOptionsAccessories.views(for: toolID, editor: session).enumerated()), id: \.offset) { $0.element }
        }
        .popover(isPresented: $showEditor) { PresetEditorView(toolID: toolID, store: store, mode: .edit).presentationCompactAdaptation(.popover) }
        .padding(.horizontal, sizeClass == .compact ? 6 : 12)
        .optionsCapsule()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Tool options", tableName: "Editor"))
    }

    private var inkMenu: some View {
        Menu {
            Picker(selection: Binding(get: { store.inkKind(for: toolID) }, set: { store.setInkKind($0, for: toolID) })) {
                ForEach(InkKind.penChoices, id: \.self) { kind in Label(kind.title, systemImage: kind.symbolName).tag(kind) }
            } label: { Text("Ink type", tableName: "Editor") }
        } label: {
            Image(systemName: store.inkKind(for: toolID).symbolName).foregroundStyle(Theme.ink).frame(minWidth: metrics.target, minHeight: 44)
        }
        .accessibilityLabel(Text("Ink type, \(String(localized: store.inkKind(for: toolID).title))", tableName: "Editor"))
        .accessibilityIdentifier("editor.options.inkType")
    }

    private func swatch(_ preset: ToolPreset) -> some View {
        let selected = preset.id == store.selectedPresetID(for: toolID)
        return Button {
            if selected { showEditor = true } else { store.selectPreset(preset.id, for: toolID) }
        } label: {
            PresetDot(color: Color(hex: preset.colorHex), selected: selected)
                .frame(minWidth: metrics.target, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Color \(NamedColor.spokenName(forHex: preset.colorHex))", tableName: "Editor"))
        .accessibilityHint(selected ? Text("Double tap to edit this color", tableName: "Editor") : Text(""))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("editor.options.color")
    }

    private var addButton: some View {
        Button { showAdd = true } label: {
            Image(systemName: "plus.circle").foregroundStyle(Theme.inkMuted).frame(minWidth: metrics.target, minHeight: 44)
        }
        .accessibilityLabel(Text("Add color", tableName: "Editor"))
        .accessibilityIdentifier("editor.options.addColor")
        .popover(isPresented: $showAdd) {
            PresetEditorView(toolID: toolID, store: store, mode: .add).presentationCompactAdaptation(.popover)
        }
    }
}

/// Three width presets drawn as short ink strokes of that width; tapping selects one.
struct WidthDots: View {
    let toolID: ToolID
    let store: EditorPresetStore
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.colorScheme) private var scheme

    private var tint: Color {
        guard let hex = store.selectedPreset(for: toolID)?.colorHex, toolID == .pen || toolID == .highlighter else { return Theme.accent }
        return Color(hex: hex).legible(on: scheme)
    }

    var body: some View {
        let _ = store.revision   // re-read when a width preset is selected or edited
        let widths = store.widths(for: toolID)
        let target = OptionsMetrics(compact: sizeClass == .compact).target
        HStack(spacing: 0) {
            ForEach(Array(widths.values.enumerated()), id: \.offset) { index, value in
                let selected = index == widths.selectedIndex
                Button { store.selectWidth(index: index, for: toolID) } label: {
                    WidthStroke(width: value, tint: selected ? tint : Theme.inkMuted)
                        .frame(minWidth: target, minHeight: 44)
                        .background {
                            if selected {
                                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(tint.opacity(0.14)).frame(width: 34, height: 34)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(label(index), tableName: "Editor"))
                .accessibilityValue(Text("\(Int(value.rounded())) points", tableName: "Editor"))
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityIdentifier("editor.options.width.\(index)")
            }
        }
    }

    private func label(_ index: Int) -> LocalizedStringKey {
        switch index {
        case 0: "Thin"
        case 1: "Medium"
        default: "Thick"
        }
    }
}

/// Edit the selected color preset (color, width of the selected width preset) or add a new color.
struct PresetEditorView: View {
    enum Mode { case edit, add }

    let toolID: ToolID
    let store: EditorPresetStore
    let mode: Mode
    @State private var color: Color
    @State private var width: Double
    @Environment(\.dismiss) private var dismiss

    init(toolID: ToolID, store: EditorPresetStore, mode: Mode) {
        self.toolID = toolID
        self.store = store
        self.mode = mode
        let hex = store.selectedPreset(for: toolID)?.colorHex ?? "#2B2420"
        _color = State(initialValue: Color(hex: hex))
        _width = State(initialValue: store.widths(for: toolID).selected)
    }

    private var range: ClosedRange<Double> {
        let type = (toolID == .highlighter ? InkKind.marker : store.inkKind(for: toolID)).pkType
        let range = type.validWidthRange
        return Double(range.lowerBound)...Double(range.upperBound)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ColorPicker(selection: $color, supportsOpacity: false) { Text("Color", tableName: "Editor") }
                .accessibilityIdentifier("editor.preset.color")
            VStack(alignment: .leading) {
                Text("Width \(Int(width.rounded())) pt", tableName: "Editor").font(.subheadline)
                Slider(value: $width, in: range) { Text("Width", tableName: "Editor") }
                    .accessibilityIdentifier("editor.preset.width")
            }
            actions
        }
        .padding()
        .frame(minWidth: 280)
        .onChange(of: color) { _, new in if mode == .edit { store.updateSelectedColor(hex: new.hexString, for: toolID) } }
        .onChange(of: width) { _, new in applyWidth(new) }
    }

    @ViewBuilder private var actions: some View {
        if mode == .add {
            Button {
                store.addColor(hex: color.hexString, for: toolID)
                applyWidth(width)
                dismiss()
            } label: { Text("Add Color", tableName: "Editor").frame(maxWidth: .infinity) }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("editor.preset.add")
        } else if store.presets(for: toolID).count > 1 {
            Button(role: .destructive) {
                removeSelected()
                dismiss()
            } label: { Text("Remove Color", tableName: "Editor").frame(maxWidth: .infinity) }
                .buttonStyle(.bordered)
        }
    }

    private func applyWidth(_ value: Double) {
        var widths = store.widths(for: toolID)
        guard widths.values.indices.contains(widths.selectedIndex) else { return }
        widths.values[widths.selectedIndex] = value
        store.setWidths(widths, for: toolID)
    }

    private func removeSelected() {
        guard let id = store.selectedPresetID(for: toolID) else { return }
        var all = store.presets(for: toolID)
        all.removeAll { $0.id == id }
        store.setPresets(all, for: toolID)
        if let first = all.first { store.selectPreset(first.id, for: toolID) }
    }
}

extension NamedColor {
    /// What VoiceOver says for a color: its plain name, or the hex code for a string that is not a color.
    static func spokenName(forHex hex: String) -> String {
        guard let named = nearest(toHex: hex) else { return hex }
        switch named {
        case .black: return String(localized: "Black", table: "Editor")
        case .white: return String(localized: "White", table: "Editor")
        case .gray: return String(localized: "Gray", table: "Editor")
        case .red: return String(localized: "Red", table: "Editor")
        case .orange: return String(localized: "Orange", table: "Editor")
        case .yellow: return String(localized: "Yellow", table: "Editor")
        case .green: return String(localized: "Green", table: "Editor")
        case .teal: return String(localized: "Teal", table: "Editor")
        case .blue: return String(localized: "Blue", table: "Editor")
        case .purple: return String(localized: "Purple", table: "Editor")
        case .pink: return String(localized: "Pink", table: "Editor")
        case .brown: return String(localized: "Brown", table: "Editor")
        }
    }
}
