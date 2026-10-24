import OSLog
import PencilKit
import SheafnoteCore
import SwiftUI

/// Whiteboards reuse the paged editor's chrome, tools and canvas with one page that has no fixed size.
/// The editor grows that page as ink nears its edge; this file makes sure it starts roomy and never smaller than
/// what is already drawn.
enum Whiteboard {
    static let initialSize = CGSize(width: 2000, height: 2000)
    private static let log = Logger(subsystem: "co.xanom.sheafnote", category: "whiteboard")

    /// Makes sure the whiteboard has its one page and that the page covers its initial size and all of its content.
    /// Never shrinks the page and never touches ink.
    @MainActor
    static func prepareCanvas(for notebook: Notebook, services: AppServices) throws {
        do {
            let pages = try services.pages.orderedPages(of: notebook.id)
            guard let page = pages.first else {
                _ = try services.pages.addPage(to: notebook.id, at: .end, template: nil)
                return try prepareCanvas(for: notebook, services: services)
            }
            let size = requiredSize(for: page, services: services)
            guard size.width > page.widthPts || size.height > page.heightPts else { return }
            page.widthPts = size.width
            page.heightPts = size.height
            markDirty(page, fields: ["widthPts", "heightPts"])
            try services.context.save()
        } catch {
            log.error("Preparing whiteboard canvas failed: \(error.localizedDescription, privacy: .public)")
            throw DocTypesError.saveFailed(error.localizedDescription)
        }
    }

    @MainActor
    private static func requiredSize(for page: Page, services: AppServices) -> CGSize {
        let ink = page.inkData.flatMap { try? PKDrawing(data: $0).bounds }
        let frames = ((try? services.pages.elements(on: page.id)) ?? []).map(\.frame)
        let content = CanvasBounds.contentBounds(strokes: ink, elements: frames)
        return CanvasBounds.grownSize(current: CGSize(width: page.widthPts, height: page.heightPts),
                                      content: content, initial: initialSize)
    }
}

struct WhiteboardEditorFactory: DocumentEditorFactory {
    let kind = NotebookKind.whiteboard

    func makeEditor(for notebook: Notebook, host: FeatureHost) -> AnyView {
        do {
            try Whiteboard.prepareCanvas(for: notebook, services: host.services)
        } catch {
            // The board still opens at its stored size; the editor grows the page as the person draws.
            Logger(subsystem: "co.xanom.sheafnote", category: "whiteboard")
                .error("Opening whiteboard at stored size: \(error.localizedDescription, privacy: .public)")
        }
        return AnyView(EditorScaffold(notebook: notebook, host: host, sizing: .infinite(initial: Whiteboard.initialSize)))
    }
}

/// "Show Whole Board" in the whiteboard's More menu: zooms out until the whole canvas is visible.
enum WhiteboardMenu {
    static let showWholeBoard = NotebookMenuItem(
        id: "docTypes.showWholeBoard", group: .view, order: 50, kinds: [.whiteboard],
        title: LocalizedStringResource("Show Whole Board", table: "DocTypes"),
        symbolName: "arrow.up.left.and.down.right.magnifyingglass",
        isEnabled: { _ in true },
        perform: { editor in editor.setZoomScale(0, animated: true) })
}
