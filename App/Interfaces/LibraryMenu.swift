import SwiftUI
import UniformTypeIdentifiers
import SheafnoteCore

struct LibraryNewItem: Identifiable {
    let id: String
    let title: LocalizedStringResource
    let symbolName: String
    let order: Int
    let action: @MainActor (LibraryActionContext) -> Void
}

struct LibraryImportHandler {
    let id: String
    let contentTypes: [UTType]
    /// Security-scoped URLs.
    let handle: @MainActor ([URL], LibraryActionContext) async throws -> Void
}

/// Cover context menu and multi-select actions.
struct NotebookContextAction: Identifiable {
    let id: String
    let title: LocalizedStringResource
    let symbolName: String
    let order: Int
    let isDestructive: Bool
    let perform: @MainActor ([Notebook], LibraryActionContext) async throws -> Void
}

@MainActor
struct LibraryActionContext {
    let services: AppServices
    let currentFolderID: UUID?
    let present: (AnyView) -> Void
    let open: (Notebook) -> Void
    let showError: (LocalizedError) -> Void
}

@MainActor
final class LibraryMenuRegistry {
    private(set) var newItems: [LibraryNewItem] = []
    private(set) var importHandlers: [LibraryImportHandler] = []
    private(set) var notebookActions: [NotebookContextAction] = []
    private(set) var searchDestination: (@MainActor (LibraryActionContext) -> AnyView)?
    private(set) var backgroundTasks: [(id: String, run: @MainActor (AppServices) async -> Void)] = []

    /// foundation registers Notebook and Folder; doc-types: Whiteboard, Text document.
    func registerNewItem(_ item: LibraryNewItem) { newItems.append(item) }
    /// pdf-io: PDF, images, .sheafnote backup.
    func registerImportItem(_ handler: LibraryImportHandler) { importHandlers.append(handler) }
    /// pdf-io: Export.
    func registerNotebookAction(_ action: NotebookContextAction) { notebookActions.append(action) }
    /// search: the sidebar "Search" destination.
    func registerSearchDestination(_ make: @escaping @MainActor (LibraryActionContext) -> AnyView) { searchDestination = make }
    /// Run on launch and when the app returns to the foreground (search OCR, auto backup).
    func registerBackgroundTask(id: String, _ run: @escaping @MainActor (AppServices) async -> Void) {
        backgroundTasks.removeAll { $0.id == id }
        backgroundTasks.append((id, run))
    }

    var sortedNewItems: [LibraryNewItem] { newItems.sorted { $0.order < $1.order } }
    var sortedNotebookActions: [NotebookContextAction] { notebookActions.sorted { $0.order < $1.order } }
    var allImportTypes: [UTType] {
        var seen = Set<UTType>()
        return importHandlers.flatMap(\.contentTypes).filter { seen.insert($0).inserted }
    }

    /// Handler whose content types match the URL, for "Open in", drop and the file importer.
    func importHandler(for url: URL) -> LibraryImportHandler? {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return nil }
        return importHandlers.first { h in h.contentTypes.contains { type.conforms(to: $0) } }
    }
}
