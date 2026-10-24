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
                    .foregroundStyle(Theme.ink)
                    .searchCardRow(padded: false)
                    .accessibilityIdentifier("search.notebook.result.\(result.pageNumber)")
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Theme.paper)
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
        .presentationBackground(Theme.paper)
        .accessibilityIdentifier("search.notebook")
    }

    @ViewBuilder private var placeholder: some View {
        if !model.hasQuery {
            DoodleEmptyState(kind: .search,
                             title: Text("Search This Notebook", tableName: "Search"),
                             message: Text("Find words in handwriting, typed text and PDF pages.", tableName: "Search"))
        } else if model.isEmpty {
            DoodleEmptyState(kind: .search,
                             title: Text("No Results", tableName: "Search"),
                             message: Text("Nothing matches \u{201C}\(query)\u{201D}. Try another word or a shorter one.", tableName: "Search"))
        }
    }

    private func go(to pageID: UUID) {
        editor.goToPage(id: pageID, animated: true)
        dismiss()
    }
}
