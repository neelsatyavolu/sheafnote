import SheafnoteCore
import SwiftUI

/// "+ New" menu entries for whiteboards and text documents. Both are created at once with a default title (rename from
/// the cover's context menu) and opened.
enum DocumentCreation {
    static let whiteboardItem = LibraryNewItem(
        id: "whiteboard", title: LocalizedStringResource("Whiteboard", table: "DocTypes"),
        symbolName: "rectangle.and.pencil.and.ellipsis", order: 20
    ) { context in
        create(kind: .whiteboard, title: String(localized: "Untitled Whiteboard", table: "DocTypes"), cover: "blueprint", context: context)
    }

    static let textDocumentItem = LibraryNewItem(
        id: "textDocument", title: LocalizedStringResource("Text Document", table: "DocTypes"),
        symbolName: "doc.text", order: 30
    ) { context in
        create(kind: .text, title: String(localized: "Untitled Text Document", table: "DocTypes"), cover: "ledger", context: context)
    }

    @MainActor
    static func create(kind: NotebookKind, title: String, cover: String, context: LibraryActionContext) {
        do {
            let notebook = try make(kind: kind, title: title, cover: cover, services: context.services, folder: context.currentFolderID)
            context.open(notebook)
        } catch let error as LocalizedError {
            context.showError(error)
        } catch {
            context.showError(DocTypesError.createFailed(error.localizedDescription))
        }
    }

    @MainActor
    static func make(kind: NotebookKind, title: String, cover: String, services: AppServices, folder: UUID?) throws -> Notebook {
        let paperColor = services.settings.paperDefaults.color
        let notebook: Notebook
        do {
            notebook = try services.library.createNotebook(
                title: title, kind: kind, cover: CoverSpec(coverID: cover), template: TemplateSpec(kind: .blank),
                paperSize: .square, orientation: .portrait, paperColor: paperColor, in: folder)
        } catch {
            throw DocTypesError.createFailed(error.localizedDescription)
        }
        if kind == .whiteboard { try Whiteboard.prepareCanvas(for: notebook, services: services) }
        return notebook
    }
}
