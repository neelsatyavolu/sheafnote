import SwiftData
import SwiftUI
import SheafnoteCore

enum SidebarItem: Hashable {
    case documents, favorites, search, recentlyDeleted
    case folder(UUID)
}

struct FolderNode: Identifiable {
    let folder: Folder
    var children: [FolderNode]?
    var id: UUID { folder.id }

    static func tree(_ folders: [Folder], parent: UUID? = nil) -> [FolderNode] {
        folders.filter { $0.deletedAt == nil && $0.parentID == parent }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            .map { f in
                let kids = tree(folders, parent: f.id)
                return FolderNode(folder: f, children: kids.isEmpty ? nil : kids)
            }
    }
}

/// iPad: Documents, Favorites, Search, Recently Deleted and the folder tree.
struct LibrarySplitView: View {
    @Environment(FeatureHost.self) private var host
    @Environment(LibrarySession.self) private var session
    @Query private var folders: [Folder]
    @State private var selection: SidebarItem? = .documents

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            NavigationStack {
                detailRoot
                    .navigationDestination(for: UUID.self) { LibraryContentView(scope: .folder($0)) }
            }
            .id(selection)
        }
        .containerBackground(Theme.paper, for: .navigationSplitView)
    }

    private var sidebar: some View {
        List(selection: $selection) {
            Section {
                Label("Documents", systemImage: "books.vertical").tag(SidebarItem.documents)
                    .accessibilityIdentifier("sidebar.documents")
                Label("Favorites", systemImage: "star").tag(SidebarItem.favorites)
                    .accessibilityIdentifier("sidebar.favorites")
                Label("Search", systemImage: "magnifyingglass").tag(SidebarItem.search)
                    .accessibilityIdentifier("sidebar.search")
                Label("Recently Deleted", systemImage: "trash").tag(SidebarItem.recentlyDeleted)
                    .accessibilityIdentifier("sidebar.recentlyDeleted")
            }
            let tree = FolderNode.tree(folders)
            if !tree.isEmpty {
                Section {
                    OutlineGroup(tree, children: \.children) { node in
                        Label {
                            Text(node.folder.name)
                        } icon: {
                            Image(systemName: "folder.fill").foregroundStyle(FolderTint.color(for: node.id))
                        }
                        .tag(SidebarItem.folder(node.id))
                            .accessibilityIdentifier("sidebar.folder.\(node.folder.name)")
                    }
                } header: {
                    Text("Folders").font(Theme.title(.footnote))
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.paper)
        .navigationTitle("Sheafnote")
        .toolbar {
            ToolbarItem(placement: .bottomBar) {
                Button("Settings", systemImage: "gearshape") { session.present(AnyView(SettingsView())) }
                    .accessibilityIdentifier("library.settings")
            }
        }
    }

    @ViewBuilder private var detailRoot: some View {
        switch selection ?? .documents {
        case .documents: LibraryContentView(scope: .documents)
        case .favorites: LibraryContentView(scope: .favorites)
        case .recentlyDeleted: LibraryContentView(scope: .recentlyDeleted)
        case .folder(let id): LibraryContentView(scope: .folder(id))
        case .search: searchDestination
        }
    }

    @ViewBuilder private var searchDestination: some View {
        if let make = host.library.searchDestination {
            make(session.actionContext(folderID: nil))
        } else {
            TitleSearchView()
        }
    }
}

/// iPhone: one navigation stack; a menu switches between Documents, Favorites, Search and Recently Deleted.
struct LibraryPhoneView: View {
    @Environment(FeatureHost.self) private var host
    @Environment(LibrarySession.self) private var session
    @State private var root: SidebarItem = .documents

    var body: some View {
        NavigationStack {
            rootContent
                .navigationDestination(for: UUID.self) { LibraryContentView(scope: .folder($0)) }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { sectionMenu }
                }
        }
        .id(root)
    }

    @ViewBuilder private var rootContent: some View {
        switch root {
        case .documents, .folder: LibraryContentView(scope: .documents)
        case .favorites: LibraryContentView(scope: .favorites)
        case .recentlyDeleted: LibraryContentView(scope: .recentlyDeleted)
        case .search:
            if let make = host.library.searchDestination { make(session.actionContext(folderID: nil)) } else { TitleSearchView() }
        }
    }

    private var sectionMenu: some View {
        Menu {
            // Same identifiers as the iPad sidebar and bottom bar, so UI tests find one control on both devices.
            Button("Documents", systemImage: "books.vertical") { root = .documents }
                .accessibilityIdentifier("sidebar.documents")
            Button("Favorites", systemImage: "star") { root = .favorites }
                .accessibilityIdentifier("sidebar.favorites")
            Button("Search", systemImage: "magnifyingglass") { root = .search }
                .accessibilityIdentifier("sidebar.search")
            Button("Recently Deleted", systemImage: "trash") { root = .recentlyDeleted }
                .accessibilityIdentifier("sidebar.recentlyDeleted")
            Divider()
            Button("Settings", systemImage: "gearshape") { session.present(AnyView(SettingsView())) }
                .accessibilityIdentifier("library.settings")
        } label: {
            Label("Library", systemImage: "sidebar.left")
        }
        .accessibilityIdentifier("library.sectionMenu")
    }
}
