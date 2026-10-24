import SwiftUI
import SheafnoteCore

/// Thumbnail navigator: editor-owned "Pages" tab plus tabs registered by other features (bookmarks, outline).
struct PageNavigatorSheet: View {
    let session: NotebookSession
    @State private var selectedTab = "pages"
    @Environment(\.dismiss) private var dismiss

    private var extraTabs: [NavigatorTab] {
        session.host.notebookMenu.navigatorTabs.sorted { $0.order < $1.order }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !extraTabs.isEmpty {
                    Picker(selection: $selectedTab) {
                        Text("Pages", tableName: "Editor").tag("pages")
                        ForEach(extraTabs) { tab in Text(tab.title).tag(tab.id) }
                    } label: { Text("Navigator", tableName: "Editor") }
                    .pickerStyle(.segmented)
                    .padding([.horizontal, .top])
                    .accessibilityIdentifier("editor.navigator.tabs")
                }
                if selectedTab == "pages" || !extraTabs.contains(where: { $0.id == selectedTab }) {
                    PagesGridView(session: session, dismissNavigator: { dismiss() })
                } else if let tab = extraTabs.first(where: { $0.id == selectedTab }) {
                    tab.makeView(session)
                }
            }
            .navigationTitle(Text("Pages", tableName: "Editor"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Text("Done", tableName: "Editor") }
                        .accessibilityIdentifier("editor.navigator.done")
                }
            }
        }
        .accessibilityIdentifier("editor.navigator")
    }
}

/// Thumbnail grid with drag-to-reorder (fractional sort keys), select mode and per-page actions.
struct PagesGridView: View {
    let session: NotebookSession
    let dismissNavigator: () -> Void

    @State private var selecting = false
    @State private var selected: Set<UUID> = []
    @State private var confirmDelete = false
    @State private var dropTarget: UUID?

    private let columns = [GridItem(.adaptive(minimum: 130, maximum: 200), spacing: 16)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(Array(session.pageIDs.enumerated()), id: \.element) { index, id in
                    cell(index: index, id: id)
                }
            }
            .padding()
        }
        .toolbar { toolbar }
        .safeAreaInset(edge: .bottom) { if selecting { selectionBar } }
        .confirmationDialog(Text("Delete selected pages?", tableName: "Editor"), isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(role: .destructive) { deleteSelected() } label: { Text("Delete Pages", tableName: "Editor") }
        } message: {
            Text("You can bring them back with Undo.", tableName: "Editor")
        }
    }

    // MARK: Cells

    private func cell(index: Int, id: UUID) -> some View {
        let isSelected = selected.contains(id)
        let isCurrent = session.currentPageID == id
        return VStack(spacing: 6) {
            PageThumbnail(session: session, pageID: id)
                .overlay(RoundedRectangle(cornerRadius: 2).stroke(isCurrent ? Color.accentColor : .clear, lineWidth: 3))
                .overlay(alignment: .bottomTrailing) {
                    if selecting {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.title2).foregroundStyle(isSelected ? Color.accentColor : .secondary)
                            .padding(6)
                    }
                }
                .overlay(alignment: .top) {
                    if dropTarget == id { Rectangle().fill(Color.accentColor).frame(height: 4) }
                }
            Text("\(index + 1)").font(.footnote.monospacedDigit()).foregroundStyle(isCurrent ? Color.accentColor : .secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture { tap(id) }
        .draggable(id.uuidString)
        .dropDestination(for: String.self) { items, _ in drop(items, on: id) } isTargeted: { dropTarget = $0 ? id : (dropTarget == id ? nil : dropTarget) }
        .contextMenu { contextMenu(for: id) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Page \(index + 1)", tableName: "Editor"))
        .accessibilityAddTraits(isSelected || isCurrent ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("editor.thumb.\(index + 1)")
        .accessibilityAction(named: Text("Move Earlier", tableName: "Editor")) { nudge(id, by: -1) }
        .accessibilityAction(named: Text("Move Later", tableName: "Editor")) { nudge(id, by: 1) }
    }

    @ViewBuilder
    private func contextMenu(for id: UUID) -> some View {
        Button { present(AddPageSheet(session: session, anchorPageID: id, placement: .before)) } label: {
            Label { Text("Add Page Before", tableName: "Editor") } icon: { Image(systemName: "arrow.up.doc") }
        }
        Button { present(AddPageSheet(session: session, anchorPageID: id, placement: .after)) } label: {
            Label { Text("Add Page After", tableName: "Editor") } icon: { Image(systemName: "arrow.down.doc") }
        }
        Button { session.duplicatePages([id]) } label: {
            Label { Text("Duplicate", tableName: "Editor") } icon: { Image(systemName: "plus.square.on.square") }
        }
        Button { present(ChangeTemplateSheet(session: session, pageIDs: [id])) } label: {
            Label { Text("Change Template", tableName: "Editor") } icon: { Image(systemName: "square.grid.3x3") }
        }
        ForEach(session.host.notebookMenu.pageMenuItems.sorted { $0.order < $1.order }) { item in
            Button { run(item, on: [id]) } label: { Label { Text(item.title) } icon: { Image(systemName: item.symbolName) } }
        }
        Button(role: .destructive) { session.deletePages([id]) } label: {
            Label { Text("Delete", tableName: "Editor") } icon: { Image(systemName: "trash") }
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { selecting.toggle(); selected = [] } label: {
                Text(selecting ? "Cancel" : "Select", tableName: "Editor")
            }
            .accessibilityIdentifier("editor.navigator.select")
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button { present(AddPageSheet(session: session)) } label: { Image(systemName: "plus") }
                .accessibilityLabel(Text("Add Page", tableName: "Editor"))
                .accessibilityIdentifier("editor.navigator.add")
        }
    }

    private var selectionBar: some View {
        HStack(spacing: 18) {
            Button { session.duplicatePages(orderedSelection); selecting = false; selected = [] } label: {
                Label { Text("Duplicate", tableName: "Editor") } icon: { Image(systemName: "plus.square.on.square") }
            }
            Button { present(ChangeTemplateSheet(session: session, pageIDs: orderedSelection)) } label: {
                Label { Text("Template", tableName: "Editor") } icon: { Image(systemName: "square.grid.3x3") }
            }
            ForEach(session.host.notebookMenu.pageMenuItems.sorted { $0.order < $1.order }) { item in
                Button { run(item, on: orderedSelection) } label: { Label { Text(item.title) } icon: { Image(systemName: item.symbolName) } }
            }
            Button(role: .destructive) { confirmDelete = true } label: {
                Label { Text("Delete", tableName: "Editor") } icon: { Image(systemName: "trash") }
            }
            .accessibilityIdentifier("editor.navigator.delete")
        }
        .labelStyle(.iconOnly)
        .disabled(selected.isEmpty)
        .padding(.horizontal, 20).padding(.vertical, 10)
        .glassEffect(.regular, in: Capsule())
        .padding(.bottom, 8)
    }

    // MARK: Actions

    private var orderedSelection: [UUID] { session.pageIDs.filter { selected.contains($0) } }

    private func tap(_ id: UUID) {
        if selecting {
            if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
        } else {
            session.goToPage(id: id, animated: false)
            dismissNavigator()
        }
    }

    private func drop(_ items: [String], on target: UUID) -> Bool {
        dropTarget = nil
        guard let raw = items.first, let dragged = UUID(uuidString: raw), dragged != target,
              let from = session.pageIDs.firstIndex(of: dragged), let to = session.pageIDs.firstIndex(of: target) else { return false }
        session.movePage(dragged, relativeTo: target, after: from < to)
        return true
    }

    private func nudge(_ id: UUID, by delta: Int) {
        guard let index = session.pageIDs.firstIndex(of: id) else { return }
        let target = index + delta
        guard session.pageIDs.indices.contains(target) else { return }
        session.movePage(id, relativeTo: session.pageIDs[target], after: delta > 0)
    }

    private func deleteSelected() {
        session.deletePages(orderedSelection)
        selecting = false
        selected = []
    }

    private func present<Content: View>(_ content: Content) {
        session.present(EditorSheet { AnyView(content) })
    }

    private func run(_ item: PageMenuItem, on ids: [UUID]) {
        Task {
            do { try await item.perform(ids, session) } catch { session.report(error) }
        }
    }
}

/// One page's thumbnail, rendered lazily and cached.
struct PageThumbnail: View {
    let session: NotebookSession
    let pageID: UUID
    @State private var image: CGImage?

    var body: some View {
        let size = session.pageSizes[pageID] ?? CGSize(width: 595, height: 842)
        ZStack {
            Rectangle().fill(Color(.systemBackground))
            if let image { Image(decorative: image, scale: 2).resizable().scaledToFit() }
        }
        .aspectRatio(size.width / max(size.height, 1), contentMode: .fit)
        .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
        .task(id: session.layoutRevision) {
            image = await session.services.pageRenderer.thumbnail(pageID: pageID, width: 360)
        }
    }
}
