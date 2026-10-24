import SwiftUI
import SheafnoteCore

/// Eraser options: whole-stroke or partial, three sizes, "erase highlighter only" and "switch back to the previous tool".
struct EraserOptionsRow: View {
    let session: NotebookSession

    var body: some View {
        let prefs = session.prefs
        HStack(spacing: 8) {
            Picker(selection: Binding(get: { prefs.values.eraserMode }, set: { prefs.values.eraserMode = $0 })) {
                Text("Stroke", tableName: "Editor").tag(EraserMode.stroke)
                Text("Partial", tableName: "Editor").tag(EraserMode.partial)
            } label: { Text("Eraser type", tableName: "Editor") }
            .pickerStyle(.segmented)
            .frame(maxWidth: 190)
            .disabled(prefs.values.eraserHighlighterOnly)
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
                Image(systemName: "slider.horizontal.3").frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel(Text("Eraser options", tableName: "Editor"))
            .accessibilityIdentifier("editor.eraser.options")
        }
        .padding(.horizontal, 12)
        .optionsCapsule()
    }
}
