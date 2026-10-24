import SwiftUI
import SheafnoteCore

@MainActor
protocol DocumentEditorFactory {
    var kind: NotebookKind { get }
    func makeEditor(for notebook: Notebook, host: FeatureHost) -> AnyView
}

/// Picks the editor for a notebook kind. Shows a placeholder when no feature has registered one; never crashes.
@MainActor
final class DocumentRouter {
    private var factories: [NotebookKind: any DocumentEditorFactory] = [:]

    func register(_ factory: any DocumentEditorFactory) { factories[factory.kind] = factory }

    func editor(for notebook: Notebook, host: FeatureHost) -> AnyView {
        if let factory = factories[notebook.kind] { return factory.makeEditor(for: notebook, host: host) }
        return AnyView(PlaceholderEditorView(notebook: notebook, services: host.services))
    }
}
