import SwiftUI
import SheafnoteCore

/// Registers the paged-notebook editor: tools (pen, highlighter, eraser), the base page layers, the page renderer,
/// the editor for `.paged` notebooks and the "Pencil & gestures" settings section.
enum EditorFeature: FeatureModule {
    static let id = "editor"

    static func register(into host: FeatureHost) {
        EditorPreferences.shared = EditorPreferences(settings: host.services.settings)

        host.tools.register(PenTool())
        host.tools.register(EraserTool())
        host.tools.register(HighlighterTool())

        host.layers.register(PaperLayerProvider())
        host.layers.register(TemplateLayerProvider())
        host.layers.register(ElementLayerProvider(slot: .belowInk, host: host))
        host.layers.register(InkLayerProvider(host: host))
        host.layers.register(ElementLayerProvider(slot: .aboveInk, host: host))

        host.services.pageRenderer = EditorPageRenderer(host: host)
        host.documents.register(PagedEditorFactory())
        host.settings.register(PencilSettingsSection.section)
    }
}

struct PagedEditorFactory: DocumentEditorFactory {
    let kind = NotebookKind.paged

    func makeEditor(for notebook: Notebook, host: FeatureHost) -> AnyView {
        AnyView(EditorRoot(notebook: notebook, host: host))
    }
}
