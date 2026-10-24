import Foundation
import Observation
import SheafnoteCore

struct TitleResult: Identifiable {
    enum Target {
        case notebook(UUID)
        case folder(UUID)
    }

    let id: SearchDocumentID
    let title: String
    let snippet: SearchSnippet
    let target: Target
    let isTextDocument: Bool
}

struct PageResult: Identifiable {
    var id: SearchDocumentID { hit.documentID }
    let hit: SearchHit
    let pageID: UUID
    let notebookID: UUID
    let notebookTitle: String
    let pageNumber: Int
}

/// Turns raw index hits into rows (titles, page numbers) for the library and notebook search screens.
@MainActor @Observable
final class SearchResultsModel {
    private(set) var titles: [TitleResult] = []
    private(set) var pages: [PageResult] = []
    private(set) var hasQuery = false

    @ObservationIgnored private let services: AppServices
    @ObservationIgnored private let service: SearchService
    @ObservationIgnored private let notebookID: UUID?
    @ObservationIgnored private let pageLimit = 150

    /// `notebookID` limits results to pages of that notebook (in-notebook search).
    init(service: SearchService, notebookID: UUID? = nil) {
        self.service = service
        self.services = service.services
        self.notebookID = notebookID
    }

    var isEmpty: Bool { titles.isEmpty && pages.isEmpty }

    func update(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        hasQuery = !SearchTokenizer.terms(in: trimmed).isEmpty
        guard hasQuery else {
            titles = []
            pages = []
            return
        }
        let hits = service.search(trimmed, notebookID: notebookID)
        titles = notebookID == nil ? hits.compactMap(titleResult) : []
        var order: [UUID: [UUID]] = [:]
        pages = hits.filter { $0.documentID.kind == .page }.prefix(pageLimit).compactMap { pageResult($0, order: &order) }
    }

    private func titleResult(_ hit: SearchHit) -> TitleResult? {
        let id = hit.documentID.id
        switch hit.documentID.kind {
        case .folderTitle:
            guard let folder = services.library.folder(id: id) else { return nil }
            return TitleResult(id: hit.documentID, title: folder.name, snippet: hit.snippet, target: .folder(id), isTextDocument: false)
        case .notebookTitle:
            guard let notebook = services.library.notebook(id: id) else { return nil }
            return TitleResult(id: hit.documentID, title: notebook.title, snippet: hit.snippet, target: .notebook(id), isTextDocument: false)
        case .textDocument:
            guard let notebook = services.library.notebook(id: id) else { return nil }
            return TitleResult(id: hit.documentID, title: notebook.title, snippet: hit.snippet, target: .notebook(id), isTextDocument: true)
        case .page:
            return nil
        }
    }

    private func pageResult(_ hit: SearchHit, order: inout [UUID: [UUID]]) -> PageResult? {
        guard let page = services.pages.page(id: hit.documentID.id),
              let notebook = services.library.notebook(id: page.notebookID) else { return nil }
        if order[notebook.id] == nil {
            order[notebook.id] = (try? services.pages.orderedPages(of: notebook.id).map(\.id)) ?? []
        }
        let number = (order[notebook.id]?.firstIndex(of: page.id)).map { $0 + 1 } ?? 1
        return PageResult(hit: hit, pageID: page.id, notebookID: notebook.id, notebookTitle: notebook.title, pageNumber: number)
    }
}

/// Identity of "this query against this version of the index"; a `.task(id:)` re-runs when either changes.
struct SearchQueryKey: Hashable {
    let text: String
    let revision: Int
}
