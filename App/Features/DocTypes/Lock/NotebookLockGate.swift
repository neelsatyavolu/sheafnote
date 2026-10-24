import SheafnoteCore
import SwiftUI

/// Wraps a notebook's editor: shows the editor when the notebook is unlocked, and a lock screen otherwise.
/// The editor is only built after authentication, so a locked notebook's ink is never loaded or drawn.
struct NotebookLockGate: View {
    let notebook: Notebook
    let content: () -> AnyView
    @State private var controller = AppLockController.shared

    var body: some View {
        if controller.requiresUnlock(notebook) {
            LockedNotebookScreen(notebook: notebook, controller: controller)
        } else {
            content()
        }
    }
}

private struct LockedNotebookScreen: View {
    let notebook: Notebook
    let controller: AppLockController
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        LockPanel(
            title: Text("\(notebook.title) is Locked", tableName: "DocTypes"),
            controller: controller,
            unlock: { Task { await controller.unlockNotebook(notebook.id) } },
            continueAnyway: { controller.continueWithoutAuthentication(notebookID: notebook.id) },
            secondary: AnyView(
                Button { dismiss() } label: { Text("Back to Library", tableName: "DocTypes") }
                    .accessibilityIdentifier("lock.back")))
            .accessibilityIdentifier("lock.notebook")
            .task { await controller.unlockNotebook(notebook.id) }
    }
}
