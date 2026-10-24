import SwiftUI
import SheafnoteCore

/// The Recovered area: page versions kept after a sync conflict (and snapshots taken before destructive edits).
/// Restoring always makes a new page; deleting asks first.
struct RecoveredPagesView: View {
    let services: AppServices
    @State private var items: [RecoveredItem] = []
    @State private var pendingDelete: RecoveredItem?
    @State private var errorMessage: String?
    @State private var restoredMessage: String?

    private var area: RecoveredArea { RecoveredArea(context: services.context) }

    var body: some View {
        List {
            if items.isEmpty {
                DoodleEmptyState(kind: .tray,
                                 title: Text("Nothing Recovered", tableName: "Sync"),
                                 message: Text("Versions of pages that Sheafnote had to set aside appear here and are kept for 30 days.", tableName: "Sync"))
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            }
            ForEach(items) { item in row(item) }
        }
        .paperList()
        .navigationTitle(Text("Recovered Pages", tableName: "Sync"))
        .navigationBarTitleDisplayMode(.inline)
        .task { reload() }
        .confirmationDialog(Text("Delete this recovered version?", tableName: "Sync"), isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible) {
            Button(String(localized: "Delete Permanently", table: "Sync"), role: .destructive) { deletePending() }
        } message: {
            Text("It can't be brought back after this.", tableName: "Sync")
        }
        .alert(Text("Recovered Pages", tableName: "Sync"), isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
        .alert(Text("Page Restored", tableName: "Sync"), isPresented: Binding(get: { restoredMessage != nil }, set: { if !$0 { restoredMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(restoredMessage ?? "") }
    }

    private func row(_ item: RecoveredItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.notebookTitle ?? String(localized: "Deleted notebook", table: "Sync")).font(.headline).foregroundStyle(Theme.ink)
            Text(reasonText(item.reason)).font(.subheadline).foregroundStyle(Theme.ink)
            Text("\(item.strokeCount) strokes, saved \(item.createdAt.formatted(date: .abbreviated, time: .shortened))", tableName: "Sync")
                .font(.footnote).foregroundStyle(Theme.inkMuted)
            Text("Kept until \(item.expiresAt.formatted(date: .abbreviated, time: .omitted))", tableName: "Sync")
                .font(.footnote).foregroundStyle(Theme.inkMuted)
        }
        .accessibilityElement(children: .combine)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { pendingDelete = item } label: { Label { Text("Delete", tableName: "Sync") } icon: { Image(systemName: "trash") } }
            Button { restore(item) } label: { Label { Text("Restore as New Page", tableName: "Sync") } icon: { Image(systemName: "arrow.uturn.backward") } }
                .tint(.accentColor)
        }
        .contextMenu {
            Button { restore(item) } label: { Label { Text("Restore as New Page", tableName: "Sync") } icon: { Image(systemName: "arrow.uturn.backward") } }
            Button(role: .destructive) { pendingDelete = item } label: { Label { Text("Delete", tableName: "Sync") } icon: { Image(systemName: "trash") } }
        }
        .accessibilityAction(named: Text("Restore as New Page", tableName: "Sync")) { restore(item) }
        .accessibilityAction(named: Text("Delete", tableName: "Sync")) { pendingDelete = item }
    }

    private func reasonText(_ reason: RevisionReason) -> String {
        switch reason {
        case .conflict: String(localized: "Kept after a sync conflict", table: "Sync")
        case .beforeDelete: String(localized: "Saved before a page was deleted", table: "Sync")
        case .beforeClear: String(localized: "Saved before a page was cleared", table: "Sync")
        case .restore: String(localized: "Saved before a restore", table: "Sync")
        }
    }

    private func reload() {
        do { items = try area.items() } catch { errorMessage = error.localizedDescription }
    }

    private func restore(_ item: RecoveredItem) {
        do {
            _ = try area.restore(item.id)
            restoredMessage = String(localized: "The recovered version was added to the notebook as a new page.", table: "Sync")
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deletePending() {
        guard let item = pendingDelete else { return }
        pendingDelete = nil
        do {
            try area.delete(item.id)
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
