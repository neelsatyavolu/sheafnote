import SwiftUI
import SheafnoteCore

/// The library's "Search" destination: titles of notebooks and folders, typed text, PDF text and handwriting
/// across everything, with page thumbnails that highlight the hits.
struct LibrarySearchView: View {
    let context: LibraryActionContext
    let service: SearchService

    @Environment(FeatureHost.self) private var host
    @State private var model: SearchResultsModel
    @State private var highlighter: HitHighlighter
    @State private var query = ""

    init(context: LibraryActionContext, service: SearchService) {
        self.context = context
        self.service = service
        _model = State(initialValue: SearchResultsModel(service: service))
        _highlighter = State(initialValue: HitHighlighter(services: service.services))
    }

    var body: some View {
        List {
            if !model.titles.isEmpty { titleSection }
            if !model.pages.isEmpty { pageSection }
        }
        .overlay { placeholder }
        .searchable(text: $query, prompt: Text("Handwriting, text, PDFs and titles", tableName: "Search"))
        .navigationTitle(Text("Search", tableName: "Search"))
        .task(id: SearchQueryKey(text: query, revision: service.revision)) {
            if !query.isEmpty { try? await Task.sleep(for: .milliseconds(180)) }
            guard !Task.isCancelled else { return }
            model.update(query: query)
        }
        .task { await service.refreshIndex() }
        .accessibilityIdentifier("search.library")
    }

    private var titleSection: some View {
        Section {
            ForEach(model.titles) { result in
                titleRow(result)
            }
        } header: {
            Text("Notebooks and Folders", tableName: "Search")
        }
    }

    @ViewBuilder
    private func titleRow(_ result: TitleResult) -> some View {
        switch result.target {
        case .folder(let id):
            NavigationLink(value: id) { Label(result.title, systemImage: "folder") }
                .accessibilityIdentifier("search.result.title.\(result.title)")
        case .notebook(let id):
            Button { openNotebook(id, page: nil) } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Label(result.title, systemImage: result.isTextDocument ? "doc.text" : "book.closed")
                    if result.isTextDocument {
                        Text(SnippetText.attributed(result.snippet)).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
            }
            .foregroundStyle(.primary)
            .accessibilityIdentifier("search.result.title.\(result.title)")
        }
    }

    private var pageSection: some View {
        Section {
            ForEach(model.pages) { result in
                Button { openNotebook(result.notebookID, page: result.pageID) } label: {
                    PageHitRow(result: result, showsNotebookTitle: true, services: service.services, highlighter: highlighter)
                }
                .foregroundStyle(.primary)
                .accessibilityIdentifier("search.result.page.\(result.notebookTitle).\(result.pageNumber)")
            }
        } header: {
            Text("Pages", tableName: "Search")
        } footer: {
            if service.ocr.pendingCount > 0 {
                Text("Still reading handwriting on \(service.ocr.pendingCount) pages. Search will find more once that's done.", tableName: "Search")
            }
        }
    }

    @ViewBuilder private var placeholder: some View {
        if !model.hasQuery {
            ContentUnavailableView {
                Label { Text("Search Your Library", tableName: "Search") } icon: { Image(systemName: "magnifyingglass") }
            } description: {
                Text("Find words in your handwriting, typed text, PDFs and notebook names.", tableName: "Search")
            }
        } else if model.isEmpty {
            ContentUnavailableView.search(text: query)
        }
    }

    private func openNotebook(_ id: UUID, page: UUID?) {
        guard let notebook = host.services.library.notebook(id: id) else {
            context.showError(SearchNavigationError.notebookMissing)
            return
        }
        context.open(notebook)
        if let page { Task { await NotebookNavigator.goToPage(page, in: id, host: host) } }
    }
}

enum SearchNavigationError: LocalizedError {
    case notebookMissing

    var errorDescription: String? {
        String(localized: "That notebook is no longer in your library. It may have been deleted on another device.", table: "Search")
    }
}
