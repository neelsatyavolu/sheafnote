import SwiftUI
import SheafnoteCore

/// Long-press menu on a cover or folder: rename, change cover, duplicate, move, favorite, registered actions, delete.
struct LibraryContextMenu: View {
    let entry: LibraryEntry
    let scope: LibraryScope
    let folderID: UUID?
    let onRename: (LibraryItemRef, String) -> Void

    @Environment(LibrarySession.self) private var session
    @Environment(FeatureHost.self) private var host

    private var actions: LibraryActions { LibraryActions(session: session) }

    var body: some View {
        if scope == .recentlyDeleted {
            Button("Restore", systemImage: "arrow.uturn.backward") { actions.restore([entry.ref]) }
        } else {
            liveMenu
        }
    }

    @ViewBuilder private var liveMenu: some View {
        Button("Rename", systemImage: "pencil") { onRename(entry.ref, entry.title) }
        if case .notebook(let n) = entry {
            Button("Change Cover", systemImage: "paintpalette") {
                session.present(AnyView(ChangeCoverSheet(notebookID: n.id)))
            }
            Button("Duplicate", systemImage: "plus.square.on.square") { actions.duplicate(n) }
        }
        Button("Move", systemImage: "folder") {
            session.present(AnyView(MoveToFolderSheet(items: [entry.ref], onDone: {})))
        }
        Button {
            actions.setFavorite([entry.ref], !entry.isFavorite)
        } label: {
            entry.isFavorite ? Label("Remove from Favorites", systemImage: "star.slash") : Label("Add to Favorites", systemImage: "star")
        }
        if case .notebook(let n) = entry {
            ForEach(host.library.sortedNotebookActions.filter { !$0.isDestructive }) { action in
                Button { actions.perform(action, on: [n], folderID: folderID) } label: {
                    Label(action.title, systemImage: action.symbolName)
                }
            }
        }
        Divider()
        Button("Delete", systemImage: "trash", role: .destructive) { actions.delete([entry.ref]) }
    }
}
