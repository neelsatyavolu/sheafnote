import SwiftUI
import SheafnoteCore

/// The magnified writing strip. The strip floats at the bottom of the screen; this tool owns the focus box on the page
/// (move it with Apple Pencil) and the options row (magnification, margins, auto-advance).
@MainActor
final class ZoomWindowTool: EditorTool {
    let id = ToolID.zoomWindow
    let title = LocalizedStringResource("Zoom Window", table: "Present")
    let symbolName = "text.magnifyingglass"
    let placement = ToolPlacement.more(order: 20)
    let supportedKinds: Set<NotebookKind> = [.paged, .whiteboard]
    let inputPolicy = ToolInputPolicy.overlayCapturesPencil

    func activate(in editor: EditorContext) {
        let controller = ZoomWindowController.controller(for: editor)
        controller.activate()
        ZoomPanelPresenter.shared.show(controller: controller, notebookID: editor.notebook.id)
    }

    func deactivate(in editor: EditorContext) {
        ZoomWindowController.controller(for: editor).deactivate()
        ZoomPanelPresenter.shared.hide()
    }

    func makeOptionsView(in editor: EditorContext) -> AnyView {
        AnyView(ZoomOptionsView(controller: ZoomWindowController.controller(for: editor)))
    }

    func makeOverlay(for page: PageContext, in editor: EditorContext) -> AnyView? {
        AnyView(ZoomFocusOverlay(page: page, controller: ZoomWindowController.controller(for: editor)))
    }
}

/// The focus box on the page. Pencil touches move it; fingers keep scrolling and zooming the page.
struct ZoomFocusOverlay: View {
    let page: any PageContext
    let controller: ZoomWindowController

    var body: some View {
        let rect = controller.model.focusRect
        ZStack(alignment: .topLeading) {
            Color.clear
            if controller.pageID == page.pageID {
                RoundedRectangle(cornerRadius: 3 / max(page.zoomScale, 0.1))
                    .fill(Theme.accent.opacity(0.14))
                    .overlay(RoundedRectangle(cornerRadius: 3 / max(page.zoomScale, 0.1))
                        .strokeBorder(Theme.accent, lineWidth: 2 / max(page.zoomScale, 0.1)))
                    .frame(width: rect.width, height: rect.height)
                    .offset(x: rect.minX, y: rect.minY)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: page.pageSize.width, height: page.pageSize.height)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { controller.focus(on: page, center: $0.location) }
        )
        .accessibilityHidden(true)
    }
}
