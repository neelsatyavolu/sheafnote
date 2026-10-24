import SwiftUI
import SheafnoteCore

/// Editor bar item: bookmarks or un-bookmarks the page being viewed.
struct BookmarkBarButton: View {
    let editor: any EditorContext

    @State private var isMarked = false

    var body: some View {
        let pageID = editor.currentPage?.pageID
        Button { toggle(pageID) } label: {
            Label {
                isMarked ? Text("Remove bookmark from this page", tableName: "Search") : Text("Bookmark this page", tableName: "Search")
            } icon: {
                Image(systemName: isMarked ? "bookmark.fill" : "bookmark")
            }
        }
        .disabled(pageID == nil)
        .accessibilityIdentifier("search.bookmark")
        .task(id: pageID) { refresh(pageID) }
        .onReceive(NotificationCenter.default.publisher(for: .sheafnoteModelDidChange)) { _ in refresh(pageID) }
    }

    private var store: BookmarkStore { BookmarkStore(context: editor.services.context) }

    private func refresh(_ pageID: UUID?) {
        guard let pageID else { isMarked = false; return }
        do { isMarked = try store.isBookmarked(pageID: pageID) } catch {
            editor.showToast(LocalizedStringResource("Couldn't read bookmarks: \(error.localizedDescription)", table: "Search"))
        }
    }

    private func toggle(_ pageID: UUID?) {
        guard let pageID else { return }
        do {
            isMarked = try store.toggle(pageID: pageID, notebookID: editor.notebook.id)
            editor.showToast(isMarked ? LocalizedStringResource("Page bookmarked", table: "Search")
                                      : LocalizedStringResource("Bookmark removed", table: "Search"))
        } catch {
            editor.showToast(LocalizedStringResource("Couldn't change the bookmark: \(error.localizedDescription)", table: "Search"))
        }
    }
}
