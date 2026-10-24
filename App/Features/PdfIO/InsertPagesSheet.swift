import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import SheafnoteCore

enum InsertPlacement: Hashable { case afterCurrent, beforeCurrent, atEnd }

/// "Insert PDF Pages…": adds the pages of a PDF, or one page per image, to the open notebook.
struct InsertPagesSheet: View {
    let editor: any EditorContext
    @State private var placement = InsertPlacement.afterCurrent
    @State private var showPDFPicker = false
    @State private var showImagePicker = false
    @State private var photos: [PhotosPickerItem] = []
    @State private var working = false
    @State private var message: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(selection: $placement) {
                        if editor.currentPage != nil {
                            Text("After the current page", tableName: "PdfIO").tag(InsertPlacement.afterCurrent)
                            Text("Before the current page", tableName: "PdfIO").tag(InsertPlacement.beforeCurrent)
                        }
                        Text("At the end", tableName: "PdfIO").tag(InsertPlacement.atEnd)
                    } label: { Text("Insert", tableName: "PdfIO") }
                    .accessibilityIdentifier("insert.placement")
                }
                Section {
                    Button { showPDFPicker = true } label: { Label { Text("PDF from Files…", tableName: "PdfIO") } icon: { Image(systemName: "doc.richtext") } }
                        .accessibilityIdentifier("insert.pdf")
                    Button { showImagePicker = true } label: { Label { Text("Images from Files…", tableName: "PdfIO") } icon: { Image(systemName: "folder") } }
                        .accessibilityIdentifier("insert.images")
                    PhotosPicker(selection: $photos, matching: .images) {
                        Label { Text("Photos…", tableName: "PdfIO") } icon: { Image(systemName: "photo.on.rectangle") }
                    }
                    .accessibilityIdentifier("insert.photos")
                } footer: {
                    Text("Each PDF page or image becomes a page you can write on. The original file is kept as it is.", tableName: "PdfIO")
                }
                .disabled(working)
                if working { Section { ProgressView { Text("Inserting pages…", tableName: "PdfIO") } } }
                if let message { Section { Text(message).foregroundStyle(.red).accessibilityIdentifier("insert.error") } }
            }
            .navigationTitle(Text("Insert Pages", tableName: "PdfIO"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button { dismiss() } label: { Text("Cancel", tableName: "PdfIO") } } }
            .fileImporter(isPresented: $showPDFPicker, allowedContentTypes: [.pdf]) { result in handleFiles(result.map { [$0] }, pdf: true) }
            .fileImporter(isPresented: $showImagePicker, allowedContentTypes: [.image], allowsMultipleSelection: true) { result in
                handleFiles(result, pdf: false)
            }
            .onChange(of: photos) { _, items in if !items.isEmpty { insertPhotos(items) } }
        }
    }

    // MARK: Actions

    private func handleFiles(_ result: Result<[URL], Error>, pdf: Bool) {
        switch result {
        case .failure(let error): message = error.localizedDescription
        case .success(let urls):
            run {
                let scoped = urls.filter { $0.startAccessingSecurityScopedResource() }
                defer { scoped.forEach { $0.stopAccessingSecurityScopedResource() } }
                if pdf, let url = urls.first {
                    let data = try await FileReading.data(at: url)
                    return try await importer.insertPDF(data, filename: url.lastPathComponent, into: editor.notebook.id, at: position)
                }
                var images: [ImportedImage] = []
                for url in urls { images.append(ImportedImage(data: try await FileReading.data(at: url), filename: url.lastPathComponent)) }
                return try await importer.insertImages(images, into: editor.notebook.id, at: position)
            }
        }
    }

    private func insertPhotos(_ items: [PhotosPickerItem]) {
        run {
            let images = try await PhotoLoading.images(from: items)
            return try await importer.insertImages(images, into: editor.notebook.id, at: position)
        }
    }

    private func run(_ work: @escaping @MainActor () async throws -> PdfImportResult) {
        working = true
        message = nil
        Task { @MainActor in
            defer { working = false; photos = [] }
            do {
                let result = try await work()
                (editor as? NotebookSession)?.reloadPages()
                if let first = result.pageIDs.first { editor.goToPage(id: first, animated: true) }
                editor.showToast(LocalizedStringResource("Pages inserted", table: "PdfIO"))
                dismiss()
            } catch {
                message = error.localizedDescription
            }
        }
    }

    private var importer: PdfImporter { PdfImporter(context: editor.services.context, pages: editor.services.pages) }

    private var position: PagePosition {
        guard let current = editor.currentPage?.pageID else { return .end }
        switch placement {
        case .afterCurrent: return .after(current)
        case .beforeCurrent: return .before(current)
        case .atEnd: return .end
        }
    }
}
