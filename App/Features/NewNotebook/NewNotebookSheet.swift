import SwiftUI
import SheafnoteCore

/// Title, cover carousel, paper carousel by type, color, size and orientation.
struct NewNotebookSheet: View {
    let services: AppServices
    let folderID: UUID?
    let onCreated: (Notebook) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var cover: String
    @State private var template: TemplateSpec
    @State private var paperColor: PaperColor
    @State private var paperSize: PaperSize
    @State private var orientation: PageOrientation
    @State private var errorMessage: String?
    @ScaledMetric private var coverWidth: CGFloat = 84
    @FocusState private var titleFocused: Bool

    init(services: AppServices, folderID: UUID?, onCreated: @escaping (Notebook) -> Void) {
        self.services = services
        self.folderID = folderID
        self.onCreated = onCreated
        let d = services.settings.paperDefaults
        _cover = State(initialValue: d.coverID)
        _template = State(initialValue: d.template)
        _paperColor = State(initialValue: d.color)
        _paperSize = State(initialValue: d.size)
        _orientation = State(initialValue: d.orientation)
    }

    private var pageSize: CGSize { paperSize.size(orientation: orientation) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    preview
                    TextField("Untitled Notebook", text: $title)
                        .textFieldStyle(.roundedBorder).font(.title3)
                        .focused($titleFocused).submitLabel(.done)
                        .accessibilityLabel(Text("Notebook title"))
                        .accessibilityIdentifier("newNotebook.title")
                    section("Cover") { coverCarousel }
                    section("Paper") {
                        TemplatePickerView(template: $template, paperColor: $paperColor, pageSize: pageSize)
                    }
                    section("Size") { sizeControls }
                }
                .padding()
            }
            .navigationTitle("New Notebook")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create", action: create).accessibilityIdentifier("newNotebook.create")
                }
            }
            .alert("Couldn't Create Notebook", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(errorMessage ?? "") }
        }
        .presentationDetents([.large])
        .accessibilityIdentifier("newNotebookSheet")
    }

    private var preview: some View {
        HStack(alignment: .bottom, spacing: 24) {
            NotebookCoverView(cover: CoverSpec(coverID: cover)).frame(maxWidth: 150)
            PaperPreviewView(template: template, color: paperColor, pageSize: pageSize)
                .frame(maxWidth: pageSize.width > pageSize.height ? 190 : 130).shadow(radius: 2, y: 1)
        }
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }

    private var coverCarousel: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 14) {
                ForEach(CoverCatalog.all) { def in
                    Button { cover = def.id } label: { CoverChoice(definition: def, isSelected: cover == def.id).frame(width: coverWidth) }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(def.title))
                        .accessibilityAddTraits(cover == def.id ? [.isButton, .isSelected] : .isButton)
                        .accessibilityIdentifier("cover.\(def.id)")
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var sizeControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            let units = services.settings.units
            Picker("Size", selection: $paperSize) {
                ForEach(PaperSize.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("paper.size")
            Text(paperSize.dimensionsText(units: units)).font(.footnote).foregroundStyle(.secondary)
            Picker("Orientation", selection: $orientation) {
                ForEach(PageOrientation.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .disabled(!paperSize.supportsOrientation)
            .accessibilityIdentifier("paper.orientation")
        }
    }

    private func section<Content: View>(_ name: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(name).font(.headline).accessibilityAddTraits(.isHeader)
            content()
        }
    }

    private func create() {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let notebook = try services.library.createNotebook(
                title: name.isEmpty ? String(localized: "Untitled Notebook") : name, kind: .paged,
                cover: CoverSpec(coverID: cover), template: template, paperSize: paperSize,
                orientation: paperSize.supportsOrientation ? orientation : .portrait, paperColor: paperColor, in: folderID)
            try services.settings.savePaperDefaults(PaperDefaults(template: template, color: paperColor, size: paperSize,
                                                                  orientation: orientation, coverID: cover))
            dismiss()
            onCreated(notebook)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct NewFolderSheet: View {
    let services: AppServices
    let parentID: UUID?

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                TextField("Folder name", text: $name)
                    .accessibilityIdentifier("newFolder.name")
                    .submitLabel(.done)
            }
            .navigationTitle("New Folder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create", action: create)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                        .accessibilityIdentifier("newFolder.create")
                }
            }
            .alert("Couldn't Create Folder", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(errorMessage ?? "") }
        }
        .presentationDetents([.medium])
    }

    private func create() {
        do {
            _ = try services.library.createFolder(name: name, in: parentID)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
