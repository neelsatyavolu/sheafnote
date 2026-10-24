import SwiftUI
import SheafnoteCore

/// "Present…" from the notebook menu: choose what the audience sees, then start.
struct PresentationOptionsSheet: View {
    let editor: EditorContext
    @Bindable var controller: PresentationController
    @Environment(\.dismiss) private var dismiss
    @State private var startRequested = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label {
                        Text(controller.hasExternalDisplay
                             ? "An external display is connected. The audience sees only the page."
                             : "No display is connected. The page will fill this screen. Connect a display or start AirPlay to show it there instead.",
                             tableName: "Present")
                    } icon: {
                        Image(systemName: controller.hasExternalDisplay ? "tv" : "ipad")
                    }
                    .accessibilityIdentifier("present.status")
                }
                Section {
                    Toggle(isOn: $controller.options.hideToolbars) { Text("Hide toolbars on this device", tableName: "Present") }
                        .accessibilityIdentifier("present.option.hideToolbars")
                    Toggle(isOn: $controller.options.showLaser) { Text("Show laser pointer", tableName: "Present") }
                        .accessibilityIdentifier("present.option.laser")
                    Toggle(isOn: $controller.options.showZoomWindow) { Text("Show zoom window", tableName: "Present") }
                        .accessibilityIdentifier("present.option.zoom")
                } header: { Text("Audience view", tableName: "Present") } footer: {
                    Text("With toolbars hidden, this device shows the page full screen and you point with the laser. Turn it off to keep writing while the audience watches.",
                         tableName: "Present")
                }
                if let notice = controller.notice {
                    Section { Text(notice).foregroundStyle(.orange) }
                }
            }
            .onDisappear { if startRequested { startRequested = false; controller.start(editor: editor) } }
            .navigationTitle(Text("Present", tableName: "Present"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text("Cancel", tableName: "Present") }
                        .accessibilityIdentifier("present.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { start() } label: { Text("Start", tableName: "Present") }
                        .accessibilityIdentifier("present.start")
                }
            }
        }
    }

    /// Starts once the sheet is fully gone, so the presenter is never presented from a sheet that is closing.
    private func start() {
        startRequested = true
        dismiss()
    }
}

/// Shown in the editor's bar while presenting, so there is always a way out even with toolbars kept.
struct StopPresentingBarButton: View {
    let controller: PresentationController

    var body: some View {
        if controller.isPresenting, !controller.machine.showsDevicePresenter {
            Button { controller.stop() } label: {
                Label { Text("Stop Presenting", tableName: "Present") } icon: { Image(systemName: "stop.circle.fill") }
                    .foregroundStyle(.red)
            }
            .accessibilityIdentifier("present.stop")
        }
    }
}
