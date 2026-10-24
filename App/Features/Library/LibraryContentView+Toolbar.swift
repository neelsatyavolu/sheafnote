import SwiftUI
import SheafnoteCore

extension LibraryContentView {
    @ToolbarContentBuilder var libraryToolbar: some ToolbarContent {
        if isTrash {
            trashToolbar
        } else if isSelecting {
            selectionToolbar
        } else {
            normalToolbar
        }
    }

    @ToolbarContentBuilder private var normalToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) { SyncStatusIndicator() }
        ToolbarItemGroup(placement: .topBarTrailing) {
            if scope != .favorites {
                newMenu
            }
            Menu {
                sortMenu
                Button {
                    session.layout = session.layout == .grid ? .list : .grid
                } label: {
                    session.layout == .grid
                        ? Label("Show as List", systemImage: "list.bullet")
                        : Label("Show as Grid", systemImage: "square.grid.2x2")
                }
                .accessibilityIdentifier("library.layoutToggle")
                Button("Select", systemImage: "checkmark.circle") { isSelecting = true }
                    .accessibilityIdentifier("library.select")
            } label: {
                Label("View Options", systemImage: "ellipsis.circle")
            }
            .accessibilityIdentifier("library.viewMenu")
        }
    }

    @ViewBuilder private var sortMenu: some View {
        @Bindable var session = session
        Picker("Sort By", selection: $session.sort.field) {
            Text("Name").tag(LibrarySortField.name)
            Text("Date Created").tag(LibrarySortField.created)
            Text("Date Modified").tag(LibrarySortField.modified)
        }
        Picker("Order", selection: $session.sort.ascending) {
            Text("Ascending").tag(true)
            Text("Descending").tag(false)
        }
    }

    private var newMenu: some View {
        Menu {
            ForEach(host.library.sortedNewItems) { item in
                Button { item.action(session.actionContext(folderID: currentFolderID)) } label: {
                    Label(item.title, systemImage: item.symbolName)
                }
                .accessibilityIdentifier("library.new.\(item.id)")
            }
            if !host.library.allImportTypes.isEmpty {
                Divider()
                Button("Import…", systemImage: "square.and.arrow.down") { session.isImporterShown = true }
                    .accessibilityIdentifier("library.import")
            }
        } label: {
            Label("New", systemImage: "plus")
        }
        .accessibilityIdentifier("library.newMenu")
    }

    @ToolbarContentBuilder private var selectionToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button(selection.count == entries.count ? "Select None" : "Select All") {
                selection = selection.count == entries.count ? [] : Set(entries.map(\.ref))
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button("Done") { isSelecting = false; selection = [] }.accessibilityIdentifier("library.selectDone")
        }
        ToolbarItemGroup(placement: .bottomBar) {
            Button("Move", systemImage: "folder") { presentMove(Array(selection)) }
                .disabled(selection.isEmpty).accessibilityIdentifier("library.bulkMove")
            Spacer()
            Button("Favorite", systemImage: "star") { actions.setFavorite(Array(selection), true) }
                .disabled(selection.isEmpty)
            Spacer()
            bulkMoreMenu
            Spacer()
            Button("Delete", systemImage: "trash", role: .destructive) {
                actions.delete(Array(selection)); selection = []
            }
            .disabled(selection.isEmpty).accessibilityIdentifier("library.bulkDelete")
        }
    }

    @ViewBuilder private var bulkMoreMenu: some View {
        let selected = selectedNotebooks
        if !host.library.sortedNotebookActions.isEmpty {
            Menu {
                ForEach(host.library.sortedNotebookActions) { action in
                    Button(role: action.isDestructive ? .destructive : nil) {
                        actions.perform(action, on: selected, folderID: currentFolderID)
                    } label: { Label(action.title, systemImage: action.symbolName) }
                }
            } label: { Label("More", systemImage: "ellipsis.circle") }
                .disabled(selected.isEmpty)
        }
    }

    @ToolbarContentBuilder private var trashToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button("Empty", role: .destructive) { confirmEmptyTrash = true }
                .disabled(entries.isEmpty).accessibilityIdentifier("library.emptyTrash")
        }
        ToolbarItemGroup(placement: .bottomBar) {
            Button("Restore", systemImage: "arrow.uturn.backward") {
                actions.restore(Array(selection)); selection = []
            }
            .disabled(selection.isEmpty).accessibilityIdentifier("library.restore")
            Spacer()
            Button("Delete Permanently", systemImage: "trash", role: .destructive) { confirmDeleteForever = true }
                .disabled(selection.isEmpty).accessibilityIdentifier("library.deleteForever")
        }
    }

    var selectedNotebooks: [Notebook] {
        notebooks.filter { selection.contains(.notebook($0.id)) }
    }

    func presentMove(_ items: [LibraryItemRef]) {
        session.present(AnyView(MoveToFolderSheet(items: items) {
            isSelecting = false
            selection = []
        }))
    }
}
