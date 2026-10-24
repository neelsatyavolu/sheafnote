import SwiftUI
import SheafnoteCore

/// "Outline" tab of the page navigator: the user's entries (add, rename, indent, reorder, delete) and the PDF's
/// own outline. Tap an entry to jump to its page.
struct OutlineTabView: View {
    let editor: any EditorContext

    @Environment(\.dismiss) private var dismiss
    @State private var model: OutlineModel
    @State private var isAdding = false
    @State private var renaming: OutlineItem?
    @State private var newTitle = ""

    init(editor: any EditorContext) {
        self.editor = editor
        _model = State(initialValue: OutlineModel(notebookID: editor.notebook.id, services: editor.services))
    }

    var body: some View {
        List {
            Section {
                ForEach(model.userRows) { row in entryRow(row, editable: true) }
                    .onMove { model.move(from: $0, to: $1) }
            } header: {
                Text("My Outline", tableName: "Search").paperHeader()
            }
            if !model.pdfRows.isEmpty {
                Section {
                    ForEach(model.pdfRows) { row in entryRow(row, editable: false) }
                } header: {
                    Text("PDF Outline", tableName: "Search").paperHeader()
                }
            }
        }
        .paperList()
        .overlay { if model.userRows.isEmpty && model.pdfRows.isEmpty { emptyState } }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { EditButton().accessibilityIdentifier("search.outline.edit") }
            ToolbarItem(placement: .topBarTrailing) {
                Button { isAdding = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel(Text("Add outline entry", tableName: "Search"))
                    .accessibilityIdentifier("search.outline.add")
            }
        }
        .task { model.reload() }
        .onReceive(NotificationCenter.default.publisher(for: .sheafnoteModelDidChange)) { _ in model.reload() }
        .sheet(isPresented: $isAdding) {
            AddOutlineEntrySheet(model: model, pageID: editor.currentPage?.pageID)
                .presentationDetents([.height(260), .medium])
        }
        .alert(Text("Rename Entry", tableName: "Search"), isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField(text: $newTitle) { Text("Title", tableName: "Search") }
            Button { if let item = renaming { model.rename(item, to: newTitle) }; renaming = nil } label: { Text("Save", tableName: "Search") }
            Button(role: .cancel) { renaming = nil } label: { Text("Cancel", tableName: "Search") }
        }
        .alert(Text("Something went wrong", tableName: "Search"),
               isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button { model.errorMessage = nil } label: { Text("OK", tableName: "Search") }
        } message: { Text(model.errorMessage ?? "") }
        .accessibilityIdentifier("search.outline")
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label { Text("No Outline", tableName: "Search") } icon: { Image(systemName: "list.bullet.indent") }
        } description: {
            Text("Add entries for the pages you want to find quickly. A PDF's own outline shows up here too.", tableName: "Search")
        } actions: {
            Button { isAdding = true } label: { Text("Add Entry for This Page", tableName: "Search") }
        }
    }

    // MARK: Rows

    private func entryRow(_ row: OutlineRow, editable: Bool) -> some View {
        let item = row.item
        let number = model.pageNumber(of: item)
        return Button { open(item) } label: {
            HStack {
                Text(item.title).padding(.leading, CGFloat(row.depth) * 20)
                Spacer(minLength: 8)
                if let number { Text("\(number)").foregroundStyle(.secondary).monospacedDigit() }
            }
        }
        .foregroundStyle(.primary)
        .disabled(number == nil && editable == false)
        .swipeActions(allowsFullSwipe: false) {
            if editable {
                Button(role: .destructive) { model.remove(item) } label: { Label { Text("Delete", tableName: "Search") } icon: { Image(systemName: "trash") } }
            }
        }
        .contextMenu { if editable { menu(for: item) } }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(number.map { Text("Page \($0)", tableName: "Search") } ?? Text("Page missing", tableName: "Search"))
        .accessibilityIdentifier("search.outline.row.\(item.title)")
    }

    @ViewBuilder
    private func menu(for item: OutlineItem) -> some View {
        Button { newTitle = item.title; renaming = item } label: {
            Label { Text("Rename", tableName: "Search") } icon: { Image(systemName: "pencil") }
        }
        if let pageID = editor.currentPage?.pageID {
            Button { model.point(item, to: pageID) } label: {
                Label { Text("Point to Current Page", tableName: "Search") } icon: { Image(systemName: "arrow.turn.down.right") }
            }
        }
        Button { model.indent(item) } label: {
            Label { Text("Indent", tableName: "Search") } icon: { Image(systemName: "increase.indent") }
        }
        Button { model.outdent(item) } label: {
            Label { Text("Outdent", tableName: "Search") } icon: { Image(systemName: "decrease.indent") }
        }
        Button(role: .destructive) { model.remove(item) } label: {
            Label { Text("Delete", tableName: "Search") } icon: { Image(systemName: "trash") }
        }
    }

    private func open(_ item: OutlineItem) {
        guard let page = model.targetPage(of: item) else {
            editor.showToast(LocalizedStringResource("That page no longer exists.", table: "Search"))
            return
        }
        editor.goToPage(id: page, animated: false)
        dismiss()
    }
}

/// Names the entry for the page being viewed. Used from the outline tab and from the "more" menu.
struct AddOutlineEntrySheet: View {
    let model: OutlineModel
    let pageID: UUID?

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(text: $title) { Text("Title", tableName: "Search") }
                        .focused($focused)
                        .submitLabel(.done)
                        .onSubmit(save)
                        .accessibilityIdentifier("search.outline.title")
                } footer: {
                    Text("The entry jumps to the page you are on now.", tableName: "Search")
                }
            }
            .paperList()
            .navigationTitle(Text("New Outline Entry", tableName: "Search"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text("Cancel", tableName: "Search") }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { save() } label: { Text("Add", tableName: "Search") }
                        .disabled(!canSave)
                        .accessibilityIdentifier("search.outline.save")
                }
            }
            .onAppear {
                model.reload()
                if title.isEmpty { title = model.defaultTitle(forPage: pageID) }
                focused = true
            }
        }
    }

    private var canSave: Bool { pageID != nil && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private func save() {
        guard canSave, let pageID else { return }
        model.add(title: title, pageID: pageID)
        dismiss()
    }
}
