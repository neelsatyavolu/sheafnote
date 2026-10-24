import SwiftData
import SwiftUI
import SheafnoteCore

/// Built-in search over notebook and folder titles. The search unit replaces it with full-text search
/// by registering a destination with the library menu registry.
struct TitleSearchView: View {
    @Environment(LibrarySession.self) private var session
    @Query private var folders: [Folder]
    @Query private var notebooks: [Notebook]
    @State private var query = ""

    private var results: [LibraryEntry] { LibraryListing.search(query, folders: folders, notebooks: notebooks) }

    var body: some View {
        List {
            ForEach(results) { entry in
                Group {
                    if case .folder(let f) = entry {
                        NavigationLink(value: f.id) { Label(entry.title, systemImage: symbol(entry)) }
                    } else {
                        Button { open(entry) } label: { Label(entry.title, systemImage: symbol(entry)) }
                    }
                }
                .accessibilityIdentifier("search.result.\(entry.title)")
            }
        }
        .overlay {
            if query.isEmpty {
                ContentUnavailableView("Search Your Library", systemImage: "magnifyingglass",
                                       description: Text("Type to find notebooks and folders by name."))
            } else if results.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
        .searchable(text: $query, prompt: Text("Notebooks and folders"))
        .navigationTitle("Search")
    }

    private func symbol(_ entry: LibraryEntry) -> String {
        if case .folder = entry { "folder" } else { "book.closed" }
    }

    private func open(_ entry: LibraryEntry) {
        if case .notebook(let n) = entry { session.open(n) }
    }
}
