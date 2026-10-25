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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric private var tileMinWidth: CGFloat = 150
    @State private var gridWidth: CGFloat = 0
    @State private var gridFold: CGRect?

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
            .background(Theme.paper.ignoresSafeArea())
            .sensoryFeedback(trigger: entries.count) { old, new in new > old ? .impact(weight: .light) : nil }
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

    /// Adaptive columns, except while a fold divides the screen (iPhone Duo open like a book): then an even number of
    /// columns with a gap at least as wide as the fold, so no tile sits on the crease.
    private var gridColumns: [GridItem] {
        guard let gridFold else { return [GridItem(.adaptive(minimum: tileMinWidth), spacing: 20, alignment: .top)] }
        let spacing = max(20, gridFold.width)
        let count = FoldSpread.evenColumnCount(width: gridWidth - 40, minimum: tileMinWidth, spacing: spacing)
        return Array(repeating: GridItem(.flexible(), spacing: spacing, alignment: .top), count: count)
    }

    @ViewBuilder private var content: some View {
        if entries.isEmpty {
            emptyState
        } else if session.layout == .grid {
            ScrollView {
                LazyVGrid(columns: gridColumns, spacing: 24) {
                    ForEach(entries) { entry in
                        cell(entry).transition(reduceMotion ? .opacity : .scale(scale: 0.6).combined(with: .opacity))
                    }
                }
                .animation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.68), value: entries.map(\.id))
                .padding(.horizontal, 20).padding(.vertical, 12)
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { gridWidth = $0 }
            .onVerticalFoldChange { gridFold = $0 }
        } else {
            List(entries) { entry in
                cell(entry).listRowBackground(Theme.paperRaised).listRowSeparatorTint(Theme.rule)
            }
            .listStyle(.plain).scrollContentBackground(.hidden)
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
        .buttonStyle(CoverPressStyle())
        .contextMenu { LibraryContextMenu(entry: entry, scope: scope, folderID: currentFolderID, onRename: startRename) }
    }

    @ViewBuilder private var emptyState: some View {
        switch scope {
        case .documents:
            LibraryEmptyState(doodle: .notebook, title: "No Notebooks Yet",
                              line: "Tap the plus button to start your first notebook.")
        case .folder:
            LibraryEmptyState(doodle: .folder, title: "This Folder Is Empty",
                              line: "Tap the plus button to add a notebook here.")
        case .favorites:
            LibraryEmptyState(doodle: .star, title: "No Favorites",
                              line: "Touch and hold a notebook and choose Add to Favorites.")
        case .recentlyDeleted:
            LibraryEmptyState(doodle: .trash, title: "Nothing Deleted",
                              line: "Deleted notebooks rest here for 30 days before they go.")
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
