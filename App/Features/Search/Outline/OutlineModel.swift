import Foundation
import Observation
import SheafnoteCore

/// State and actions behind the outline screen of one notebook: the user's own entries (editable) and the
/// outline imported from a PDF (read-only).
@MainActor @Observable
final class OutlineModel {
    private(set) var userRows: [OutlineRow] = []
    private(set) var pdfRows: [OutlineRow] = []
    private(set) var pages: [OutlinePageRef] = []
    var errorMessage: String?

    @ObservationIgnored let notebookID: UUID
    @ObservationIgnored private let services: AppServices
    @ObservationIgnored private let store: OutlineStore

    init(notebookID: UUID, services: AppServices) {
        self.notebookID = notebookID
        self.services = services
        self.store = OutlineStore(context: services.context)
    }

    func reload() {
        do {
            let items = try store.items(in: notebookID)
            userRows = OutlineTree.rows(from: items.filter { $0.source == .user })
            pdfRows = OutlineTree.rows(from: items.filter { $0.source == .pdf })
            pages = try services.pages.orderedPages(of: notebookID).map {
                OutlinePageRef(id: $0.id, pdfPageIndex: $0.backgroundPageIndex)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// The notebook page an entry leads to, if it still exists.
    func targetPage(of item: OutlineItem) -> UUID? { OutlineTree.targetPage(of: item, in: pages) }

    func pageNumber(of item: OutlineItem) -> Int? {
        targetPage(of: item).flatMap { id in pages.firstIndex { $0.id == id } }.map { $0 + 1 }
    }

    func defaultTitle(forPage pageID: UUID?) -> String {
        let number = pageID.flatMap { id in pages.firstIndex { $0.id == id } }.map { $0 + 1 } ?? 1
        return String(localized: "Page \(number)", table: "Search")
    }

    // MARK: Editing

    func add(title: String, pageID: UUID) { perform { try store.add(title: title, pageID: pageID, notebookID: notebookID) } }

    func rename(_ item: OutlineItem, to title: String) { perform { try store.rename(id: item.id, to: title) } }

    func remove(_ item: OutlineItem) { perform { try store.remove(id: item.id) } }

    func point(_ item: OutlineItem, to pageID: UUID) { perform { try store.setTarget(id: item.id, pageID: pageID) } }

    /// Makes the entry a sub-entry of the entry just above it at the same level.
    func indent(_ item: OutlineItem) {
        guard let index = userRows.firstIndex(where: { $0.id == item.id }),
              let sibling = userRows[..<index].last(where: { $0.item.parentID == item.parentID }) else { return }
        perform { try store.move(id: item.id, toParent: sibling.id, before: nil) }
    }

    /// Moves a sub-entry up one level, directly after its parent.
    func outdent(_ item: OutlineItem) {
        guard let parentID = item.parentID, let parent = userRows.first(where: { $0.id == parentID })?.item else { return }
        let siblings = userRows.filter { $0.item.parentID == parent.parentID }.map(\.id)
        let next = siblings.firstIndex(of: parent.id).flatMap { siblings.indices.contains($0 + 1) ? siblings[$0 + 1] : nil }
        perform { try store.move(id: item.id, toParent: parent.parentID, before: next) }
    }

    /// Drag-to-reorder in the flat list: the entry joins the level of the row it lands before.
    func move(from source: IndexSet, to destination: Int) {
        guard let from = source.first, userRows.indices.contains(from) else { return }
        var remaining = userRows
        let moved = remaining.remove(at: from).item
        let at = destination > from ? destination - 1 : destination
        let target = remaining.indices.contains(at) ? remaining[at].item : nil
        perform { try store.move(id: moved.id, toParent: target?.parentID, before: target?.id) }
    }

    private func perform(_ work: () throws -> Void) {
        do { try work() } catch { errorMessage = error.localizedDescription }
        reload()
    }
}
