import PhotosUI
import SheafnoteCore
import SwiftUI

struct TextDocumentEditorFactory: DocumentEditorFactory {
    let kind = NotebookKind.text

    func makeEditor(for notebook: Notebook, host: FeatureHost) -> AnyView {
        AnyView(TextDocumentEditor(notebook: notebook, services: host.services))
    }
}

/// Rich text editor: headings, bulleted and numbered lists, checklists, bold/italic/underline and pictures.
/// Built from system controls; there is no pen tool row.
struct TextDocumentEditor: View {
    @State private var model: TextDocumentModel
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var imageError: String?
    @FocusState private var focus: UUID?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    init(notebook: Notebook, services: AppServices) {
        _model = State(initialValue: TextDocumentModel(notebook: notebook, services: services))
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(model.notebook.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbar }
        }
        .tint(Theme.accent)
        .accessibilityIdentifier("textdoc.root")
        .onChange(of: focus) { _, new in if let new { model.focusedBlock = new } }
        .onChange(of: model.focusedBlock) { _, new in if focus != new { focus = new } }
        .onChange(of: scenePhase) { _, phase in if phase != .active { model.flush() } }
        .onChange(of: pickedPhoto) { _, item in if let item { Task { await insert(item) } } }
        .onDisappear { model.flush() }
        .alert(Text("Couldn't Save", tableName: "DocTypes"), isPresented: Binding(
            get: { model.saveError != nil }, set: { if !$0 { model.saveError = nil } })) {
            Button(role: .cancel) {} label: { Text("OK", tableName: "DocTypes") }
        } message: { Text(model.saveError ?? "") }
        .alert(Text("Couldn't Add Picture", tableName: "DocTypes"), isPresented: Binding(
            get: { imageError != nil }, set: { if !$0 { imageError = nil } })) {
            Button(role: .cancel) {} label: { Text("OK", tableName: "DocTypes") }
        } message: { Text(imageError ?? "") }
    }

    @ViewBuilder private var content: some View {
        if let error = model.loadError {
            ContentUnavailableView {
                Label { Text("Can't Open This Document", tableName: "DocTypes") } icon: { Image(systemName: "exclamationmark.triangle") }
            } description: { Text(error) }
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    let numbers = model.document.numbers
                    ForEach(Array(model.document.blocks.enumerated()), id: \.element.id) { index, block in
                        TextBlockRow(model: model, block: block, index: index, number: numbers[index], focus: $focus)
                    }
                }
                .padding(.horizontal, 20).padding(.vertical, 16)
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.paper)
        }
    }

    // MARK: Toolbar

    private var focusedID: UUID? { focus ?? model.focusedBlock ?? model.document.blocks.last?.id }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { model.flush(); dismiss() } label: { Image(systemName: "chevron.backward") }
                .accessibilityLabel(Text("Back to library", tableName: "DocTypes"))
                .accessibilityIdentifier("textdoc.back")
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button { model.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                .disabled(!model.canUndo)
                .accessibilityLabel(Text("Undo", tableName: "DocTypes")).accessibilityIdentifier("textdoc.undo")
            Button { model.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                .disabled(!model.canRedo)
                .accessibilityLabel(Text("Redo", tableName: "DocTypes")).accessibilityIdentifier("textdoc.redo")
            ShareLink(item: model.document.plainText) { Image(systemName: "square.and.arrow.up") }
                .accessibilityLabel(Text("Share text", tableName: "DocTypes"))
        }
        ToolbarItemGroup(placement: .bottomBar) {
            styleMenu
            Button { toggle(.bold) } label: { Image(systemName: "bold") }
                .accessibilityLabel(Text("Bold", tableName: "DocTypes")).accessibilityIdentifier("textdoc.bold")
            Button { toggle(.italic) } label: { Image(systemName: "italic") }
                .accessibilityLabel(Text("Italic", tableName: "DocTypes")).accessibilityIdentifier("textdoc.italic")
            Button { toggle(.underline) } label: { Image(systemName: "underline") }
                .accessibilityLabel(Text("Underline", tableName: "DocTypes")).accessibilityIdentifier("textdoc.underline")
            Spacer()
            PhotosPicker(selection: $pickedPhoto, matching: .images) { Image(systemName: "photo") }
                .accessibilityLabel(Text("Insert picture", tableName: "DocTypes")).accessibilityIdentifier("textdoc.photo")
        }
    }

    private var styleMenu: some View {
        Menu {
            styleButton(.paragraph, "Body", "text.alignleft")
            styleButton(.heading1, "Title", "textformat.size.larger")
            styleButton(.heading2, "Heading", "textformat.size")
            styleButton(.heading3, "Subheading", "textformat.size.smaller")
            Divider()
            styleButton(.bullet, "Bulleted List", "list.bullet")
            styleButton(.numbered, "Numbered List", "list.number")
            styleButton(.checklist, "Checklist", "checklist")
            Divider()
            Button(role: .destructive) {
                if let id = focusedID { model.change { $0.removingBlock(id) } }
            } label: { Label { Text("Delete Block", tableName: "DocTypes") } icon: { Image(systemName: "trash") } }
        } label: {
            Image(systemName: "textformat")
        }
        .accessibilityLabel(Text("Text style", tableName: "DocTypes"))
        .accessibilityIdentifier("textdoc.style")
    }

    private func styleButton(_ kind: RichTextBlockKind, _ title: LocalizedStringKey, _ symbol: String) -> some View {
        Button {
            if let id = focusedID { model.change { $0.settingKind(kind, for: id) } }
        } label: { Label { Text(title, tableName: "DocTypes") } icon: { Image(systemName: symbol) } }
        .accessibilityIdentifier("textdoc.style.\(kind.rawValue)")
    }

    private func toggle(_ style: RichTextStyle) {
        if let id = focusedID { model.change { $0.togglingStyle(style, for: id) } }
    }

    private func insert(_ item: PhotosPickerItem) async {
        defer { pickedPhoto = nil }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                imageError = DocTypesError.imageUnreadable.errorDescription
                return
            }
            try model.insertImage(data: data)
        } catch {
            imageError = error.localizedDescription
        }
    }
}
