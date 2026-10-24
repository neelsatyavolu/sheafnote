import Observation
import SwiftUI
import SheafnoteCore

/// Open notebooks across the top of the editor (iPad). Each tab keeps its `NotebookSession`, so undo history and
/// zoom survive switching tabs.
@MainActor @Observable
final class EditorTabs {
    static let shared = EditorTabs()

    private(set) var openIDs: [UUID] = []
    var activeID: UUID?
    @ObservationIgnored private var sessions: [UUID: NotebookSession] = [:]
    @ObservationIgnored private var claims: [UUID: UUID] = [:]

    func session(for notebook: Notebook, host: FeatureHost, sizing: PageSizing) -> NotebookSession {
        if let existing = sessions[notebook.id] { return existing }
        let created = NotebookSession(notebook: notebook, host: host, sizing: sizing)
        sessions[notebook.id] = created
        return created
    }

    /// A notebook is live in one window at a time (two windows would fight over one canvas and could overwrite each
    /// other's ink). The first scaffold to claim it shows it; a second one shows a notice instead.
    func claim(_ notebookID: UUID, token: UUID) -> Bool {
        if let owner = claims[notebookID], owner != token { return false }
        claims[notebookID] = token
        return true
    }

    func release(_ notebookID: UUID, token: UUID) {
        if claims[notebookID] == token { claims[notebookID] = nil }
    }

    func open(_ notebook: Notebook) {
        if !openIDs.contains(notebook.id) { openIDs.append(notebook.id) }
        activeID = notebook.id
    }

    /// Flushes ink, then forgets the tab. The notebook itself is untouched.
    func close(id: UUID) {
        if let session = sessions[id] { UnsavedInkKeeper.shared.settle(session) }
        sessions[id] = nil
        guard let index = openIDs.firstIndex(of: id) else { return }
        openIDs.remove(at: index)
        if activeID == id { activeID = openIDs.indices.contains(index) ? openIDs[index] : openIDs.last }
    }

    func closeAll() {
        for id in openIDs { if let session = sessions[id] { UnsavedInkKeeper.shared.settle(session) } }
        sessions.removeAll()
        openIDs.removeAll()
        activeID = nil
    }
}

/// The editor registered for paged notebooks: optional tab strip above the scaffold of the active notebook.
struct EditorRoot: View {
    let notebook: Notebook
    let host: FeatureHost
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var tabs = EditorTabs.shared

    private var active: Notebook? {
        let id = tabs.activeID ?? notebook.id
        return id == notebook.id ? notebook : host.services.library.notebook(id: id)
    }

    var body: some View {
        VStack(spacing: 0) {
            if tabs.openIDs.count > 1, sizeClass == .regular { EditorTabStrip(tabs: tabs, host: host) }
            if let active {
                EditorScaffold(notebook: active, host: host, sizing: .fixed(.zero), allowsTabs: sizeClass == .regular, onClose: close)
                    .id(active.id)
            }
        }
        .onAppear { tabs.open(notebook) }
    }

    private func close() {
        tabs.closeAll()
        dismiss()
    }
}

struct EditorTabStrip: View {
    let tabs: EditorTabs
    let host: FeatureHost

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(tabs.openIDs, id: \.self) { id in
                    if let notebook = host.services.library.notebook(id: id) { tab(notebook) }
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
        }
        .background(.bar)
        .accessibilityIdentifier("editor.tabs")
    }

    private func tab(_ notebook: Notebook) -> some View {
        let selected = tabs.activeID == notebook.id
        return HStack(spacing: 6) {
            Button { tabs.activeID = notebook.id } label: {
                Text(notebook.title).lineLimit(1).frame(maxWidth: 180)
            }
            .accessibilityAddTraits(selected ? .isSelected : [])
            Button { tabs.close(id: notebook.id) } label: { Image(systemName: "xmark").imageScale(.small) }
                .accessibilityLabel(Text("Close tab \(notebook.title)", tableName: "Editor"))
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Capsule().fill(selected ? Color.accentColor.opacity(0.18) : Color(.secondarySystemFill)))
        .foregroundStyle(.primary)
    }
}
