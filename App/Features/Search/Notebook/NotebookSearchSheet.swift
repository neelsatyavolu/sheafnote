import SwiftUI
import SheafnoteCore

/// Search inside one notebook: the same index, limited to its pages. Tapping a result closes the sheet and scrolls
/// the notebook to that page.
struct NotebookSearchSheet: View {
    let editor: any EditorContext
    let service: SearchService

    @Environment(\.dismiss) private var dismiss
    @State private var model: SearchResultsModel
    @State private var highlighter: HitHighlighter
    @State private var query = ""

    init(editor: any EditorContext, service: SearchService) {
        self.editor = editor
        self.service = service
        _model = State(initialValue: SearchResultsModel(service: service, notebookID: editor.notebook.id))
        _highlighter = State(initialValue: HitHighlighter(services: service.services))
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(model.pages) { result in
                    Button { go(to: result.pageID) } label: {
                        PageHitRow(result: result, showsNotebookTitle: false, services: service.services, highlighter: highlighter)
                    }
                    .foregroundStyle(.primary)
                    .accessibilityIdentifier("search.notebook.result.\(result.pageNumber)")
                }
            }
            .overlay { placeholder }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: Text("Search this notebook", tableName: "Search"))
            .navigationTitle(Text("Search", tableName: "Search"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Text("Done", tableName: "Search") }
                        .accessibilityIdentifier("search.notebook.done")
                }
            }
            .task(id: SearchQueryKey(text: query, revision: service.revision)) {
                if !query.isEmpty { try? await Task.sleep(for: .milliseconds(180)) }
                guard !Task.isCancelled else { return }
                model.update(query: query)
            }
            .task { await service.refreshIndex() }
        }
        .accessibilityIdentifier("search.notebook")
    }

    @ViewBuilder private var placeholder: some View {
        if !model.hasQuery {
            ContentUnavailableView {
                Label { Text("Search This Notebook", tableName: "Search") } icon: { Image(systemName: "magnifyingglass") }
            } description: {
                Text("Find words in handwriting, typed text and PDF pages.", tableName: "Search")
            }
        } else if model.isEmpty {
            ContentUnavailableView.search(text: query)
        }
    }

    private func go(to pageID: UUID) {
        editor.goToPage(id: pageID, animated: true)
        dismiss()
    }
}
