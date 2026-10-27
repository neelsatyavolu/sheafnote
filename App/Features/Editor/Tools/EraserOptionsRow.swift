import SwiftUI
import SheafnoteCore

/// Eraser options: precision, standard or whole-stroke, three sizes, "erase highlighter only" and
/// "switch back to the previous tool".
struct EraserOptionsRow: View {
    let session: NotebookSession

    var body: some View {
        let prefs = session.prefs
        let mode = prefs.values.eraserMode
        HStack(spacing: 8) {
            Menu {
                Picker(selection: Binding(get: { prefs.values.eraserMode }, set: { prefs.values.eraserMode = $0 })) {
                    ForEach(EraserMode.allCases, id: \.self) { mode in
                        Label {
                            Text(mode.title)
                            Text(mode.detail)
                        } icon: { Image(systemName: mode.symbolName) }
                        .tag(mode)
                    }
                } label: { Text("Eraser type", tableName: "Editor") }
            } label: {
                Label { Text(mode.title) } icon: { Image(systemName: mode.symbolName) }
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(Theme.ink)
                    .frame(minHeight: 44)
            }
            .disabled(prefs.values.eraserHighlighterOnly)
            .accessibilityLabel(Text("Eraser type", tableName: "Editor"))
            .accessibilityValue(Text(mode.title))
            .accessibilityIdentifier("editor.eraser.mode")
            OptionsDivider()
            WidthDots(toolID: .eraser, store: session.presetStore)
            OptionsDivider()
            Menu {
                Toggle(isOn: Binding(get: { prefs.values.eraserHighlighterOnly }, set: { prefs.values.eraserHighlighterOnly = $0 })) {
                    Text("Erase Highlighter Only", tableName: "Editor")
                }
                Toggle(isOn: Binding(get: { prefs.values.eraserSwitchBack }, set: { prefs.values.eraserSwitchBack = $0 })) {
                    Text("Switch Back After Erasing", tableName: "Editor")
                }
            } label: {
                Image(systemName: "slider.horizontal.3").foregroundStyle(Theme.inkMuted).frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel(Text("Eraser options", tableName: "Editor"))
            .accessibilityIdentifier("editor.eraser.options")
        }
        .padding(.horizontal, 12)
        .optionsCapsule()
    }
}

extension EraserMode {
    var title: LocalizedStringResource {
        switch self {
        case .precision: LocalizedStringResource("Precision", table: "Editor")
        case .standard: LocalizedStringResource("Standard", table: "Editor")
        case .stroke: LocalizedStringResource("Stroke", table: "Editor")
        }
    }

    var detail: LocalizedStringResource {
        switch self {
        case .precision: LocalizedStringResource("Erases exactly what it touches", table: "Editor")
        case .standard: LocalizedStringResource("Erases what it touches without leaving bits behind", table: "Editor")
        case .stroke: LocalizedStringResource("Erases whole strokes", table: "Editor")
        }
    }

    var symbolName: String {
        switch self {
        case .precision: "eraser.line.dashed"
        case .standard: "eraser"
        case .stroke: "scribble.variable"
        }
    }
}
