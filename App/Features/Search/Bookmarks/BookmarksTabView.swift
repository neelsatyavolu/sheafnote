import SwiftUI
import SheafnoteCore

/// "Bookmarks" tab of the page navigator: bookmarked pages in page order. Tap to jump.
struct BookmarksTabView: View {
    let editor: any EditorContext

    @Environment(\.dismiss) private var dismiss
    @State private var items: [BookmarkItem] = []
    @State private var pageNumbers: [UUID: Int] = [:]
    @State private var renaming: BookmarkItem?
    @State private var newTitle = ""
    @State private var errorMessage: String?

    private var store: BookmarkStore { BookmarkStore(context: editor.services.context) }

    var body: some View {
        List {
            ForEach(items) { item in row(item) }
        }
        .overlay {
            if items.isEmpty {
                ContentUnavailableView {
                    Label { Text("No Bookmarks", tableName: "Search") } icon: { Image(systemName: "bookmark") }
                } description: {
                    Text("Tap the bookmark button in the toolbar to mark a page.", tableName: "Search")
                }
            }
        }
        .task { reload() }
        .onReceive(NotificationCenter.default.publisher(for: .sheafnoteModelDidChange)) { _ in reload() }
        .alert(Text("Rename Bookmark", tableName: "Search"), isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField(text: $newTitle) { Text("Name", tableName: "Search") }
            Button { commitRename() } label: { Text("Save", tableName: "Search") }
            Button(role: .cancel) { renaming = nil } label: { Text("Cancel", tableName: "Search") }
        }
        .alert(Text("Something went wrong", tableName: "Search"), isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button { errorMessage = nil } label: { Text("OK", tableName: "Search") }
        } message: { Text(errorMessage ?? "") }
        .accessibilityIdentifier("search.bookmarks")
    }

    private func row(_ item: BookmarkItem) -> some View {
        let number = pageNumbers[item.pageID]
        return Button {
            editor.goToPage(id: item.pageID, animated: false)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                PageThumbnailView(pageID: item.pageID, services: editor.services, width: 160)
                    .frame(width: 56).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title ?? pageName(number)).font(.headline)
                    if item.title != nil { Text(pageName(number)).font(.subheadline).foregroundStyle(.secondary) }
                }
                Spacer(minLength: 0)
            }
        }
        .foregroundStyle(.primary)
        .swipeActions {
            Button(role: .destructive) { remove(item) } label: { Label { Text("Remove", tableName: "Search") } icon: { Image(systemName: "bookmark.slash") } }
        }
        .contextMenu {
            Button { newTitle = item.title ?? ""; renaming = item } label: {
                Label { Text("Rename", tableName: "Search") } icon: { Image(systemName: "pencil") }
            }
            Button(role: .destructive) { remove(item) } label: {
                Label { Text("Remove Bookmark", tableName: "Search") } icon: { Image(systemName: "bookmark.slash") }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("search.bookmark.row.\(number ?? 0)")
    }

    private func pageName(_ number: Int?) -> String {
        number.map { String(localized: "Page \($0)", table: "Search") } ?? String(localized: "Missing page", table: "Search")
    }

    private func reload() {
        do {
            let order = try editor.services.pages.orderedPages(of: editor.notebook.id).map(\.id)
            pageNumbers = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0 + 1) })
            items = try store.bookmarks(in: editor.notebook.id, pageOrder: order)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func remove(_ item: BookmarkItem) {
        do { try store.remove(id: item.id) } catch { errorMessage = error.localizedDescription }
        reload()
    }

    private func commitRename() {
        guard let item = renaming else { return }
        renaming = nil
        do { try store.rename(id: item.id, to: newTitle) } catch { errorMessage = error.localizedDescription }
        reload()
    }
}
