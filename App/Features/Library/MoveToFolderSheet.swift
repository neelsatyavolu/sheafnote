import SwiftData
import SwiftUI
import SheafnoteCore

/// Pick a destination folder (or Documents) for the given items. Folders can't be moved into themselves.
struct MoveToFolderSheet: View {
    let items: [LibraryItemRef]
    let onDone: () -> Void

    @Environment(LibrarySession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @Query private var folders: [Folder]

    private struct Row: Identifiable { let folder: Folder; let depth: Int; var id: UUID { folder.id } }

    private var rows: [Row] {
        let live = folders.filter { $0.deletedAt == nil }
        var out: [Row] = []
        func walk(_ parent: UUID?, _ depth: Int) {
            let children = live.filter { $0.parentID == parent }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            for f in children {
                out.append(Row(folder: f, depth: depth))
                walk(f.id, depth + 1)
            }
        }
        walk(nil, 0)
        return out
    }

    private func isBlocked(_ folder: Folder) -> Bool {
        items.contains { item in
            guard case .folder(let id) = item else { return false }
            return LibraryStore.isFolderOrDescendant(folder.id, of: id, in: folders)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Button { move(to: nil) } label: { Label("Documents", systemImage: "books.vertical") }
                    .accessibilityIdentifier("move.documents")
                ForEach(rows) { row in
                    Button { move(to: row.folder.id) } label: {
                        Label(row.folder.name, systemImage: "folder").padding(.leading, CGFloat(row.depth) * 20)
                    }
                    .disabled(isBlocked(row.folder))
                    .accessibilityIdentifier("move.\(row.folder.name)")
                }
            }
            .navigationTitle("Move To")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func move(to folder: UUID?) {
        LibraryActions(session: session).move(items, to: folder)
        onDone()
        dismiss()
    }
}

extension LibraryStore {
    nonisolated static func isFolderOrDescendant(_ candidate: UUID, of ancestor: UUID, in folders: [Folder]) -> Bool {
        var current: UUID? = candidate
        var hops = 0
        while let id = current, hops < 64 {
            if id == ancestor { return true }
            current = folders.first { $0.id == id }?.parentID
            hops += 1
        }
        return false
    }
}
