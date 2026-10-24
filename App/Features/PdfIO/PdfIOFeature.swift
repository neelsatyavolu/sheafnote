import SwiftUI
import SheafnoteCore

/// PDFs and files: PDF/image import, PDF page backgrounds, export to PDF/images/`.sheafnote`, and backups.
enum PdfIOFeature: FeatureModule {
    static let id = "pdf-io"

    static func register(into host: FeatureHost) {
        let services = host.services
        host.layers.register(BackgroundLayerProvider(services: services, cache: BackgroundAssetCache(pages: services.pages)))

        registerLibrary(into: host)
        registerEditor(into: host)

        let backup = AutoBackupController(services: services)
        host.settings.register(BackupSettings.section(controller: backup))
        host.library.registerBackgroundTask(id: "pdfio.backup") { _ in
            ExportFolder.removeStale()
            await backup.runIfDue()
        }
        UITestHooks.installIfNeeded(into: host)
    }

    // MARK: Library

    private static func registerLibrary(into host: FeatureHost) {
        for handler in ImportActions.handlers { host.library.registerImportItem(handler) }
        host.library.registerNewItem(ImportActions.photosItem)
        host.library.registerNotebookAction(NotebookContextAction(
            id: "pdfio.export", title: LocalizedStringResource("Export…", table: "PdfIO"), symbolName: "square.and.arrow.up",
            order: 60, isDestructive: false) { notebooks, ctx in
                guard !notebooks.isEmpty else { return }
                ctx.present(AnyView(ExportOptionsSheet(model: ExportModel(services: ctx.services, notebooks: notebooks))))
            })
    }

    // MARK: Editor

    private static func registerEditor(into host: FeatureHost) {
        host.notebookMenu.registerBarItem(EditorBarItem(id: "pdfio.export", slot: .leading(order: 40), kinds: [.paged]) { editor in
            AnyView(Button { present(ExportModel(services: editor.services, notebooks: [editor.notebook],
                                                 currentPageID: editor.currentPage?.pageID), in: editor) } label: {
                Label { Text("Export", tableName: "PdfIO") } icon: { Image(systemName: "square.and.arrow.up") }
            }
            .accessibilityIdentifier("editor.export"))
        })
        host.notebookMenu.registerPageMenuItem(PageMenuItem(
            id: "pdfio.exportPages", order: 60, title: LocalizedStringResource("Export Pages…", table: "PdfIO"),
            symbolName: "square.and.arrow.up") { pageIDs, editor in
                present(ExportModel(services: editor.services, notebooks: [editor.notebook],
                                    currentPageID: editor.currentPage?.pageID, selectedPageIDs: Set(pageIDs)), in: editor)
            })
        host.notebookMenu.registerMenuItem(NotebookMenuItem(
            id: "pdfio.insert", group: .insert, order: 10, kinds: [.paged],
            title: LocalizedStringResource("Insert PDF or Images…", table: "PdfIO"), symbolName: "doc.badge.plus",
            isEnabled: { _ in true }) { editor in
                editor.present(EditorSheet(detents: [.medium, .large]) { AnyView(InsertPagesSheet(editor: editor)) })
            })
    }

    @MainActor
    private static func present(_ model: ExportModel, in editor: any EditorContext) {
        editor.present(EditorSheet(detents: [.large]) { AnyView(ExportOptionsSheet(model: model)) })
    }
}
