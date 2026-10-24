import SwiftData
import SwiftUI
import SheafnoteCore

/// The grid or list of folders and notebooks for one scope (Documents, a folder, Favorites, Recently Deleted).
struct LibraryContentView: View {
    let scope: LibraryScope

    @Environment(LibrarySession.self) var session
    @Environment(FeatureHost.self) var host
    @Query var folders: [Folder]
    @Query var notebooks: [Notebook]
    @State var isSelecting = false
    @State var selection: Set<LibraryItemRef> = []
    @State var renameTarget: LibraryItemRef?
    @State var renameText = ""
    @State var confirmEmptyTrash = false
    @State var confirmDeleteForever = false
    @ScaledMetric private var tileMinWidth: CGFloat = 150

    var actions: LibraryActions { LibraryActions(session: session) }
    var isTrash: Bool { scope == .recentlyDeleted }
    var showsSelection: Bool { isSelecting || isTrash }

    var currentFolderID: UUID? {
        if case .folder(let id) = scope { return id }
        return nil
    }

    var entries: [LibraryEntry] {
        LibraryListing.entries(scope: scope, folders: folders, notebooks: notebooks, sort: session.sort)
    }

    var title: String {
        switch scope {
        case .documents: String(localized: "Documents")
        case .favorites: String(localized: "Favorites")
        case .recentlyDeleted: String(localized: "Recently Deleted")
        case .folder(let id): folders.first { $0.id == id }?.name ?? String(localized: "Folder")
        }
    }

    var body: some View {
        content
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.large)
            .toolbar { libraryToolbar }
            .alert("Rename", isPresented: renameBinding) { renameAlertContent }
            .confirmationDialog("Empty Recently Deleted?", isPresented: $confirmEmptyTrash, titleVisibility: .visible) {
                Button("Delete All Permanently", role: .destructive) { actions.emptyTrash(); selection = [] }
            } message: { Text("These items will be deleted forever. This can't be undone.") }
            .confirmationDialog("Delete permanently?", isPresented: $confirmDeleteForever, titleVisibility: .visible) {
                Button("Delete Permanently", role: .destructive) { actions.deleteForever(Array(selection)); selection = [] }
            } message: { Text("The selected items will be deleted forever. This can't be undone.") }
            .dropDestination(for: URL.self) { urls, _ in
                LibraryImporter(session: session, host: host).handle(urls, folderID: currentFolderID)
            }
    }

    @ViewBuilder private var content: some View {
        if entries.isEmpty {
            emptyState
        } else if session.layout == .grid {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: tileMinWidth), spacing: 20, alignment: .top)], spacing: 24) {
                    ForEach(entries) { entry in cell(entry) }
                }
                .padding(.horizontal, 20).padding(.vertical, 12)
            }
        } else {
            List(entries) { entry in cell(entry) }.listStyle(.plain)
        }
    }

    @ViewBuilder private func cell(_ entry: LibraryEntry) -> some View {
        let selected = selection.contains(entry.ref)
        let days = entry.deletedAt.map { LibraryListing.daysRemaining(deletedAt: $0) }
        let count = LibraryListing.childCount(of: entry.id, folders: folders, notebooks: notebooks)
        let label = Group {
            if session.layout == .grid {
                LibraryTile(entry: entry, childCount: count, isSelecting: showsSelection, isSelected: selected, deletedDaysLeft: days)
            } else {
                LibraryRow(entry: entry, childCount: count, isSelecting: showsSelection, isSelected: selected, deletedDaysLeft: days)
            }
        }
        Group {
            if showsSelection {
                Button { toggle(entry.ref) } label: { label }
            } else if case .folder(let f) = entry {
                NavigationLink(value: f.id) { label }
            } else if case .notebook(let n) = entry {
                Button { session.open(n) } label: { label }
            }
        }
        .buttonStyle(.plain)
        .contextMenu { LibraryContextMenu(entry: entry, scope: scope, folderID: currentFolderID, onRename: startRename) }
    }

    @ViewBuilder private var emptyState: some View {
        switch scope {
        case .documents:
            ContentUnavailableView("No Notebooks Yet", systemImage: "books.vertical",
                                   description: Text("Tap the plus button to create a notebook."))
        case .folder:
            ContentUnavailableView("This Folder Is Empty", systemImage: "folder",
                                   description: Text("Tap the plus button to add a notebook here."))
        case .favorites:
            ContentUnavailableView("No Favorites", systemImage: "star",
                                   description: Text("Touch and hold a notebook and choose Add to Favorites."))
        case .recentlyDeleted:
            ContentUnavailableView("Nothing Deleted", systemImage: "trash",
                                   description: Text("Deleted notebooks stay here for 30 days before they are removed."))
        }
    }

    func toggle(_ ref: LibraryItemRef) {
        if selection.contains(ref) { selection.remove(ref) } else { selection.insert(ref) }
    }

    func startRename(_ ref: LibraryItemRef, current: String) {
        renameText = current
        renameTarget = ref
    }

    private var renameBinding: Binding<Bool> {
        Binding(get: { renameTarget != nil }, set: { if !$0 { renameTarget = nil } })
    }

    @ViewBuilder private var renameAlertContent: some View {
        TextField("Name", text: $renameText)
        Button("Cancel", role: .cancel) { renameTarget = nil }
        Button("Rename") {
            if let target = renameTarget { actions.rename(target, to: renameText) }
            renameTarget = nil
        }
    }
}
