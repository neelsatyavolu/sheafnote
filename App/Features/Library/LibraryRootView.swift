import SwiftUI
import SheafnoteCore

/// The library: a split view with a sidebar on iPad, a navigation stack on iPhone.
struct LibraryRootView: View {
    @Environment(FeatureHost.self) private var host
    @State private var session: LibrarySession?

    var body: some View {
        Group {
            if let session {
                LibraryShell(session: session)
                    .environment(session)
            } else {
                ProgressView()
            }
        }
        .task { if session == nil { session = LibrarySession(services: host.services) } }
    }
}

private struct LibraryShell: View {
    @Bindable var session: LibrarySession
    @Environment(FeatureHost.self) private var host
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        Group {
            // An iPad window that is narrow (Split View, Slide Over, a small Stage Manager window) is compact: it gets the
            // phone layout, like the editor does.
            if UIDevice.current.userInterfaceIdiom == .pad, horizontalSizeClass != .compact {
                LibrarySplitView()
            } else {
                LibraryPhoneView()
            }
        }
        .sheet(item: $session.sheet) { presented in
            presented.content.environment(session).environment(host).environment(host.services)
        }
        .fullScreenCover(item: $session.openTarget) { target in
            OpenedNotebookView(notebookID: target.id)
        }
        .alert(item: $session.alert) { alert in
            Alert(title: Text(alert.title), message: Text(alert.message), dismissButton: .default(Text("OK")))
        }
        .fileImporter(isPresented: $session.isImporterShown, allowedContentTypes: host.library.allImportTypes,
                      allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): LibraryImporter(session: session, host: host).handle(urls, folderID: nil)
            case .failure(let error): session.show(error)
            }
        }
        .onOpenURL { url in LibraryImporter(session: session, host: host).handle([url], folderID: nil) }
    }
}

/// Resolves the notebook and asks the document router for its editor. Never crashes if the notebook vanished.
struct OpenedNotebookView: View {
    let notebookID: UUID
    @Environment(FeatureHost.self) private var host
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if let notebook = host.services.library.notebook(id: notebookID), notebook.deletedAt == nil {
            host.documents.editor(for: notebook, host: host)
        } else {
            ContentUnavailableView {
                Label("Notebook Not Found", systemImage: "questionmark.folder")
            } description: {
                Text("It may have been deleted on another device.")
            } actions: {
                Button("Back to Library") { dismiss() }
            }
        }
    }
}
