import SwiftUI
import SheafnoteCore

/// Settings section "Pencil & gestures" (order 10).
enum PencilSettingsSection {
    static let section = SettingsSection(
        id: "editor.pencil", order: 10,
        title: LocalizedStringResource("Pencil & Gestures", table: "Editor"), symbolName: "applepencil.gen2"
    ) { services in
        AnyView(PencilSettingsContent(prefs: EditorPreferences.shared ?? EditorPreferences(settings: services.settings)))
    }
}

private struct PencilSettingsContent: View {
    let prefs: EditorPreferences

    var body: some View {
        Section {
            Picker(selection: Binding(get: { prefs.inputMode }, set: { prefs.inputMode = $0 })) {
                Text("Pencil or Finger", tableName: "Editor").tag(InputMode.anyInput)
                Text("Pencil Only", tableName: "Editor").tag(InputMode.pencilOnly)
            } label: { Text("Draw With", tableName: "Editor") }
            .accessibilityIdentifier("settings.editor.inputMode")
        } footer: {
            Text("With Pencil Only, fingers scroll and zoom and never leave a mark. With Pencil or Finger, scroll with two fingers.", tableName: "Editor")
        }
        Section {
            actionPicker(Text("Double-Tap", tableName: "Editor"), selection: Binding(get: { prefs.values.doubleTap }, set: { prefs.values.doubleTap = $0 }))
                .accessibilityIdentifier("settings.editor.doubleTap")
            actionPicker(Text("Squeeze", tableName: "Editor"), selection: Binding(get: { prefs.values.squeeze }, set: { prefs.values.squeeze = $0 }))
                .accessibilityIdentifier("settings.editor.squeeze")
        } header: {
            Text("Apple Pencil", tableName: "Editor")
        } footer: {
            Text("Squeeze needs an Apple Pencil Pro. Double-tap needs Apple Pencil (2nd generation) or later.", tableName: "Editor")
        }
        Section {
            Toggle(isOn: Binding(get: { prefs.values.eraserSwitchBack }, set: { prefs.values.eraserSwitchBack = $0 })) {
                Text("Switch Back After Erasing", tableName: "Editor")
            }
            Toggle(isOn: Binding(get: { prefs.values.eraserHighlighterOnly }, set: { prefs.values.eraserHighlighterOnly = $0 })) {
                Text("Erase Highlighter Only", tableName: "Editor")
            }
        } header: {
            Text("Eraser", tableName: "Editor")
        }
    }

    private func actionPicker(_ title: Text, selection: Binding<PencilTapAction>) -> some View {
        Picker(selection: selection) {
            Text("Switch Between Eraser and Current Tool", tableName: "Editor").tag(PencilTapAction.switchToEraser)
            Text("Switch to Previous Tool", tableName: "Editor").tag(PencilTapAction.switchToPrevious)
            Text("Show Color Palette", tableName: "Editor").tag(PencilTapAction.showPalette)
            Text("Off", tableName: "Editor").tag(PencilTapAction.off)
        } label: { title }
    }
}
