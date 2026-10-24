import SwiftUI

struct RootView: View {
    let bootstrap: AppBootstrap
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        switch bootstrap.state {
        case .ready(let host):
            LibraryRootView()
                .appLockCover()
                .environment(host)
                .environment(host.services)
                .modelContainer(host.services.container)
                .task { await runBackgroundTasks(host) }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { Task { await runBackgroundTasks(host) } }
                }
        case .failed(let message):
            StoreFailureView(message: message)
        }
    }

    private func runBackgroundTasks(_ host: FeatureHost) async {
        for task in host.library.backgroundTasks { await task.run(host.services) }
    }
}

/// Shown if the library cannot be opened. Nothing is deleted or reset.
struct StoreFailureView: View {
    let message: String

    var body: some View {
        ContentUnavailableView {
            Label("Your library can't be opened", systemImage: "exclamationmark.triangle")
        } description: {
            Text("Sheafnote did not change or delete anything. Restart the app; if this keeps happening, update Sheafnote or free up storage on this device.\n\n\(message)")
        }
        .accessibilityIdentifier("storeFailure")
    }
}
