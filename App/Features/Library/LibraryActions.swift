import SwiftUI
import SheafnoteCore

/// Library mutations with errors routed to the session's alert. Nothing here deletes data permanently
/// except `deleteForever`, which the UI only offers behind a confirmation in Recently Deleted.
@MainActor
struct LibraryActions {
    let session: LibrarySession
    var services: AppServices { session.services }

    func rename(_ item: LibraryItemRef, to name: String) {
        run { try services.library.rename(item, to: name) }
    }

    func setFavorite(_ items: [LibraryItemRef], _ value: Bool) {
        run { try services.library.setFavorite(items, value) }
    }

    func delete(_ items: [LibraryItemRef]) {
        run { try services.library.softDelete(items) }
    }

    func restore(_ items: [LibraryItemRef]) {
        run { try services.library.restore(items) }
    }

    func deleteForever(_ items: [LibraryItemRef]) {
        run { try services.library.deletePermanently(items) }
    }

    func duplicate(_ notebook: Notebook) {
        run { try services.library.duplicate(notebook, copySuffix: String(localized: " copy")) }
    }

    func move(_ items: [LibraryItemRef], to folder: UUID?) {
        run { try services.library.move(items, to: folder) }
    }

    func setCover(_ notebookID: UUID, _ cover: CoverSpec) {
        run { try services.library.setCover(notebookID, to: cover) }
    }

    func emptyTrash() {
        run {
            let entries = LibraryListing.trash(folders: try services.library.allFolders(), notebooks: try services.library.allNotebooks())
            try services.library.deletePermanently(entries.map(\.ref))
        }
    }

    func perform(_ action: NotebookContextAction, on notebooks: [Notebook], folderID: UUID?) {
        let ctx = session.actionContext(folderID: folderID)
        Task {
            do { try await action.perform(notebooks, ctx) } catch { session.show(error) }
        }
    }

    private func run(_ body: () throws -> some Any) {
        do { _ = try body() } catch { session.show(error) }
    }
}
