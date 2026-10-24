import SwiftUI
import SheafnoteCore

/// Add a page before or after the current one, or at the end, with a choice of paper.
struct AddPageSheet: View {
    enum Placement: Hashable { case after, before, end }

    let session: NotebookSession
    /// When set, the page is added next to this page instead of the current one (thumbnail context menu).
    var anchorPageID: UUID?
    var initialPlacement: Placement = .after

    @State private var placement: Placement
    @State private var template: TemplateSpec
    @State private var paperColor: PaperColor
    @Environment(\.dismiss) private var dismiss

    init(session: NotebookSession, anchorPageID: UUID? = nil, placement: Placement = .after) {
        self.session = session
        self.anchorPageID = anchorPageID
        self.initialPlacement = placement
        _placement = State(initialValue: placement)
        _template = State(initialValue: session.notebook.template)
        _paperColor = State(initialValue: session.notebook.paperColorValue)
    }

    private var anchor: UUID? { anchorPageID ?? session.currentPageID }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(selection: $placement) {
                        Text("After This Page", tableName: "Editor").tag(Placement.after)
                        Text("Before This Page", tableName: "Editor").tag(Placement.before)
                        Text("At the End", tableName: "Editor").tag(Placement.end)
                    } label: { Text("Position", tableName: "Editor") }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("editor.addPage.position")
                }
                Section {
                    TemplatePickerView(template: $template, paperColor: $paperColor, pageSize: session.notebook.pageSize)
                } header: { Text("Paper", tableName: "Editor") }
            }
            .navigationTitle(Text("Add Page", tableName: "Editor"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text("Cancel", tableName: "Editor") }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { add() } label: { Text("Add", tableName: "Editor") }
                        .accessibilityIdentifier("editor.addPage.confirm")
                }
            }
        }
    }

    private func add() {
        let position: PagePosition
        switch (placement, anchor) {
        case (.after, let id?): position = .after(id)
        case (.before, let id?): position = .before(id)
        default: position = .end
        }
        session.addPage(position, template: template, paperColor: paperColor)
        dismiss()
    }
}

/// Change the paper of this page or of every page.
struct ChangeTemplateSheet: View {
    let session: NotebookSession
    var pageIDs: [UUID]?

    @State private var template: TemplateSpec
    @State private var paperColor: PaperColor
    @Environment(\.dismiss) private var dismiss

    init(session: NotebookSession, pageIDs: [UUID]? = nil) {
        self.session = session
        self.pageIDs = pageIDs
        let page = (pageIDs?.first ?? session.currentPageID).flatMap { session.services.pages.page(id: $0) }
        _template = State(initialValue: page?.template ?? session.notebook.template)
        _paperColor = State(initialValue: page?.paperColorOverrideValue ?? session.notebook.paperColorValue)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TemplatePickerView(template: $template, paperColor: $paperColor, pageSize: session.notebook.pageSize)
                }
                Section {
                    Button { apply(to: targets) } label: {
                        Text(pageIDs == nil ? "Apply to This Page" : "Apply to Selected Pages", tableName: "Editor")
                    }
                    .accessibilityIdentifier("editor.template.applyPage")
                    Button { apply(to: session.pageIDs) } label: { Text("Apply to All Pages", tableName: "Editor") }
                        .accessibilityIdentifier("editor.template.applyAll")
                } footer: {
                    Text("Your writing is not changed, only the paper behind it. You can undo this.", tableName: "Editor")
                }
            }
            .navigationTitle(Text("Page Template", tableName: "Editor"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text("Cancel", tableName: "Editor") }
                }
            }
        }
    }

    private var targets: [UUID] { pageIDs ?? session.currentPageID.map { [$0] } ?? [] }

    private func apply(to ids: [UUID]) {
        session.changeTemplate(pageIDs: ids, template: template, paperColor: paperColor)
        dismiss()
    }
}

/// Pick another notebook to open in a new tab.
struct NotebookPickerSheet: View {
    let session: NotebookSession
    @Environment(\.dismiss) private var dismiss

    private var notebooks: [Notebook] {
        ((try? session.services.library.allNotebooks()) ?? [])
            .filter { $0.deletedAt == nil && $0.kind == .paged && $0.id != session.notebook.id }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            List(notebooks, id: \.id) { notebook in
                Button {
                    EditorTabs.shared.open(session.notebook)
                    EditorTabs.shared.open(notebook)
                    dismiss()
                } label: { Text(notebook.title) }
            }
            .overlay {
                if notebooks.isEmpty {
                    ContentUnavailableView {
                        Label { Text("No Other Notebooks", tableName: "Editor") } icon: { Image(systemName: "books.vertical") }
                    }
                }
            }
            .navigationTitle(Text("Open in Tab", tableName: "Editor"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text("Cancel", tableName: "Editor") }
                }
            }
        }
    }
}
