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
    /// Wraps every editor before it is built (doc-types uses it to ask for Face ID / passcode on locked notebooks).
    /// `content` builds the real editor and must only be called once the notebook may be opened.
    var gate: (@MainActor (Notebook, @escaping () -> AnyView) -> AnyView)?

    func register(_ factory: any DocumentEditorFactory) { factories[factory.kind] = factory }

    func editor(for notebook: Notebook, host: FeatureHost) -> AnyView {
        let build: () -> AnyView = { [self] in
            if let factory = factories[notebook.kind] { return factory.makeEditor(for: notebook, host: host) }
            return AnyView(PlaceholderEditorView(notebook: notebook, services: host.services))
        }
        guard let gate else { return build() }
        return gate(notebook, build)
    }
}
