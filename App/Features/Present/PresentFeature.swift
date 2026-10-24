import SwiftUI
import SheafnoteCore

/// Presenting: laser pointer, zoom window, presentation mode on an external display or on the device, and
/// "Open in New Window" for notebooks.
enum PresentFeature: FeatureModule {
    static let id = "present"

    private static let drawingKinds: Set<NotebookKind> = [.paged, .whiteboard]

    static func register(into host: FeatureHost) {
        host.tools.register(LaserTool())
        host.tools.register(ZoomWindowTool())
        host.notebookMenu.registerMenuItem(presentMenuItem)
        host.notebookMenu.registerBarItem(stopBarItem)
        host.library.registerNotebookAction(openInNewWindowAction)
    }

    private static var presentMenuItem: NotebookMenuItem {
        NotebookMenuItem(
            id: "present", group: .view, order: 50, kinds: drawingKinds,
            title: LocalizedStringResource("Present…", table: "Present"), symbolName: "play.rectangle",
            isEnabled: { _ in true },
            perform: { editor in
                let controller = PresentationController.shared
                if controller.isPresenting { return controller.stop() }
                editor.present(EditorSheet(detents: [.medium, .large]) {
                    AnyView(PresentationOptionsSheet(editor: editor, controller: controller))
                })
            })
    }

    private static var stopBarItem: EditorBarItem {
        EditorBarItem(id: "present.stop", slot: .trailing(order: 5), kinds: drawingKinds,
                      makeView: { _ in AnyView(StopPresentingBarButton(controller: PresentationController.shared)) })
    }

    private static var openInNewWindowAction: NotebookContextAction {
        NotebookContextAction(
            id: "present.openInNewWindow", title: LocalizedStringResource("Open in New Window", table: "Present"),
            symbolName: "macwindow.badge.plus", order: 40, isDestructive: false,
            perform: { notebooks, _ in
                guard let notebook = notebooks.first else { return }
                try NotebookWindowActivity.openInNewWindow(notebook)
            })
    }
}
