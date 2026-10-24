import SwiftUI
import SheafnoteCore

/// Finding things: library and in-notebook search over handwriting, typed text, PDFs and titles; bookmarks;
/// outline; links. Handwriting is read in the background by `OCRIndexer`.
enum SearchFeature: FeatureModule {
    static let id = "search"

    static func register(into host: FeatureHost) {
        let service = SearchService(services: host.services)
        SearchService.shared = service
        service.startObserving()
        registerLibrary(into: host, service: service)
        registerEditor(into: host, service: service)
        registerLinks(into: host)
        host.settings.register(SearchSettingsSection.section(service: service))
    }

    private static func registerLibrary(into host: FeatureHost, service: SearchService) {
        host.library.registerSearchDestination { context in
            AnyView(LibrarySearchView(context: context, service: service))
        }
        // Starts the work and returns at once, so it never delays the other launch tasks.
        host.library.registerBackgroundTask(id: "search.index") { _ in service.kickOff() }
    }

    private static func registerEditor(into host: FeatureHost, service: SearchService) {
        let menu = host.notebookMenu
        menu.registerBarItem(EditorBarItem(id: "search.find", slot: .leading(order: 20), kinds: [.paged, .whiteboard]) { editor in
            AnyView(NotebookSearchButton(editor: editor, service: service))
        })
        menu.registerBarItem(EditorBarItem(id: "search.bookmark", slot: .leading(order: 21), kinds: [.paged]) { editor in
            AnyView(BookmarkBarButton(editor: editor))
        })
        menu.registerNavigatorTab(NavigatorTab(id: "bookmarks", order: 10, title: LocalizedStringResource("Bookmarks", table: "Search"),
                                               symbolName: "bookmark") { editor in AnyView(BookmarksTabView(editor: editor)) })
        menu.registerNavigatorTab(NavigatorTab(id: "outline", order: 20, title: LocalizedStringResource("Outline", table: "Search"),
                                               symbolName: "list.bullet.indent") { editor in AnyView(OutlineTabView(editor: editor)) })
        menu.registerMenuItem(NotebookMenuItem(
            id: "search.addOutline", group: .tools, order: 40, kinds: [.paged],
            title: LocalizedStringResource("Add Outline Entry…", table: "Search"), symbolName: "list.bullet.indent",
            isEnabled: { $0.currentPage != nil },
            perform: { editor in
                let model = OutlineModel(notebookID: editor.notebook.id, services: editor.services)
                let pageID = editor.currentPage?.pageID
                editor.present(EditorSheet(detents: [.height(260), .medium]) {
                    AnyView(AddOutlineEntrySheet(model: model, pageID: pageID))
                })
            }))
    }

    private static func registerLinks(into host: FeatureHost) {
        host.elementRenderers.register(LinkElementRenderer(host: host))
        host.selectionActions.register(LinkToSelectionAction())
    }
}

/// Editor bar item: opens search for this notebook.
private struct NotebookSearchButton: View {
    let editor: any EditorContext
    let service: SearchService

    var body: some View {
        Button {
            editor.present(EditorSheet(detents: [.large]) { AnyView(NotebookSearchSheet(editor: editor, service: service)) })
        } label: {
            // A Label, not a bare Image: on iPhone this button sits in the editor's "more" menu and needs a title.
            Label { Text("Search in notebook", tableName: "Search") } icon: { Image(systemName: "magnifyingglass") }
        }
        .keyboardShortcut("f", modifiers: .command)
        .accessibilityIdentifier("search.notebook.button")
    }
}
