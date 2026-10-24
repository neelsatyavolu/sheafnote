import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import SheafnoteCore

/// The library's import entries: PDFs, images and `.sheafnote` backups arrive here from the file importer, drag and
/// drop and "Open in". Each handler creates NEW notebooks; nothing existing is touched.
@MainActor
enum ImportActions {
    static let archiveType = UTType(exportedAs: "co.xanom.sheafnote.archive", conformingTo: .data)

    static var handlers: [LibraryImportHandler] {
        [
            LibraryImportHandler(id: "pdfio.pdf", contentTypes: [.pdf]) { urls, ctx in try await importPDFs(urls, ctx) },
            LibraryImportHandler(id: "pdfio.images", contentTypes: [.image]) { urls, ctx in try await importImages(urls, ctx) },
            LibraryImportHandler(id: "pdfio.archive", contentTypes: [archiveType]) { urls, ctx in try await importArchives(urls, ctx) },
        ]
    }

    static var photosItem: LibraryNewItem {
        LibraryNewItem(id: "pdfio.photos", title: LocalizedStringResource("Notebook from Photos", table: "PdfIO"),
                       symbolName: "photo.on.rectangle", order: 40) { ctx in
            ctx.present(AnyView(PhotosNotebookSheet(context: ctx)))
        }
    }

    // MARK: PDF

    static func importPDFs(_ urls: [URL], _ ctx: LibraryActionContext) async throws {
        let importer = PdfImporter(context: ctx.services.context, pages: ctx.services.pages)
        var last: PdfImportResult?
        for url in urls {
            let data = try await FileReading.data(at: url)
            let title = url.deletingPathExtension().lastPathComponent
            last = try await importer.importPDF(data, title: title, into: ctx.currentFolderID)
        }
        Haptics.light()
        open(last, urls.count, ctx)
    }

    // MARK: Images

    static func importImages(_ urls: [URL], _ ctx: LibraryActionContext) async throws {
        var images: [ImportedImage] = []
        for url in urls { images.append(ImportedImage(data: try await FileReading.data(at: url), filename: url.lastPathComponent)) }
        let title = urls.count == 1 ? urls[0].deletingPathExtension().lastPathComponent : String(localized: "Imported Images", table: "PdfIO")
        let importer = PdfImporter(context: ctx.services.context, pages: ctx.services.pages)
        let result = try await importer.importImages(images, title: title, into: ctx.currentFolderID)
        Haptics.light()
        open(result, 1, ctx)
    }

    // MARK: Backups

    static func importArchives(_ urls: [URL], _ ctx: LibraryActionContext) async throws {
        var notebooks = 0, pages = 0
        for url in urls {
            let summary = try await ArchiveRestore.run(url: url, folderID: ctx.currentFolderID, services: ctx.services)
            notebooks += summary.notebookIDs.count
            pages += summary.pageCount
        }
        Haptics.light()
        ctx.present(AnyView(ImportSummarySheet(notebooks: notebooks, pages: pages)))
    }

    private static func open(_ result: PdfImportResult?, _ count: Int, _ ctx: LibraryActionContext) {
        guard count == 1, let result, let notebook = ctx.services.library.notebook(id: result.notebookID) else { return }
        ctx.open(notebook)
    }
}

/// Restores a `.sheafnote` file as new copies. A whole-library backup goes into its own dated folder.
@MainActor
enum ArchiveRestore {
    static func run(url: URL, folderID: UUID?, services: AppServices) async throws -> ArchiveImportSummary {
        let importer = ArchiveImporter(context: services.context, pages: services.pages)
        let manifest = try importer.inspect(url: url)
        let wrapper = manifest.scope == .library
            ? String(localized: "Sheafnote Backup \(manifest.createdAt.formatted(date: .abbreviated, time: .omitted))", table: "PdfIO")
            : nil
        return try await importer.importArchive(from: url, into: folderID, wrapperFolderName: wrapper)
    }
}

struct ImportSummarySheet: View {
    let notebooks: Int
    let pages: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 48)).foregroundStyle(.green).accessibilityHidden(true)
                Text("Backup imported", tableName: "PdfIO").font(.title2.bold())
                VStack {
                    LabeledContent { Text(notebooks, format: .number) } label: { Text("Notebooks added", tableName: "PdfIO") }
                    LabeledContent { Text(pages, format: .number) } label: { Text("Pages added", tableName: "PdfIO") }
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("import.summary")
                Text("They are new copies. Nothing that was already here was changed.", tableName: "PdfIO")
                    .multilineTextAlignment(.center).foregroundStyle(.secondary)
            }
            .padding()
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button { dismiss() } label: { Text("Done", tableName: "PdfIO") } } }
        }
        .presentationDetents([.medium])
    }
}

/// "Notebook from Photos": choose pictures, get a notebook with one page per picture.
struct PhotosNotebookSheet: View {
    let context: LibraryActionContext
    @State private var picked: [PhotosPickerItem] = []
    @State private var working = false
    @State private var message: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "photo.on.rectangle").font(.system(size: 48)).foregroundStyle(.tint).accessibilityHidden(true)
                Text("Each photo becomes a page you can write on.", tableName: "PdfIO").multilineTextAlignment(.center)
                PhotosPicker(selection: $picked, matching: .images, photoLibrary: .shared()) {
                    Text("Choose Photos", tableName: "PdfIO")
                }
                .buttonStyle(.borderedProminent)
                .disabled(working)
                .accessibilityIdentifier("photos.choose")
                if working { ProgressView().accessibilityLabel(Text("Importing", tableName: "PdfIO")) }
                if let message { Text(message).foregroundStyle(.red).font(.footnote) }
            }
            .padding()
            .navigationTitle(Text("Notebook from Photos", tableName: "PdfIO"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button { dismiss() } label: { Text("Cancel", tableName: "PdfIO") } } }
            .onChange(of: picked) { _, items in if !items.isEmpty { Task { await importPicked(items) } } }
        }
        .presentationDetents([.medium])
    }

    private func importPicked(_ items: [PhotosPickerItem]) async {
        working = true
        defer { working = false }
        do {
            let images = try await PhotoLoading.images(from: items)
            let title = String(localized: "Photos \(Date.now.formatted(date: .abbreviated, time: .omitted))", table: "PdfIO")
            let importer = PdfImporter(context: context.services.context, pages: context.services.pages)
            let result = try await importer.importImages(images, title: title, into: context.currentFolderID)
            Haptics.light()
            dismiss()
            if let notebook = context.services.library.notebook(id: result.notebookID) { context.open(notebook) }
        } catch {
            message = error.localizedDescription
        }
    }
}

enum PhotoLoading {
    @MainActor
    static func images(from items: [PhotosPickerItem]) async throws -> [ImportedImage] {
        var out: [ImportedImage] = []
        for (index, item) in items.enumerated() {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                throw PdfIOError.unreadableImage(String(localized: "photo \(index + 1)", table: "PdfIO"))
            }
            out.append(ImportedImage(data: data, filename: nil))
        }
        return out
    }
}
