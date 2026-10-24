import SwiftUI
import SheafnoteCore

/// Tap the page to type a text box; tap an existing one to edit it.
@MainActor
final class TextTool: EditorTool {
    let id = ToolID.text
    let title = LocalizedStringResource("Text", table: "Elements")
    let symbolName = "textformat"
    let placement = ToolPlacement.primary(order: 70)
    let supportedKinds: Set<NotebookKind> = [.paged, .whiteboard]
    let inputPolicy = ToolInputPolicy.overlayCapturesAll

    private let editing: TextEditSession
    private unowned let host: FeatureHost

    init(editing: TextEditSession, host: FeatureHost) {
        self.editing = editing
        self.host = host
    }

    func activate(in editor: EditorContext) { editor.selection.clear() }

    /// Leaving the tool (or the page) finishes the edit, so no typing is ever lost.
    func deactivate(in editor: EditorContext) {
        // The tool (and its box) is going away, so a failed write cannot be retried here: report it and drop the edit
        // (the stored version of an existing box is untouched).
        if !TextEditing.commit(editing, editor: editor) { editing.cancel() }
    }

    func makeOptionsView(in editor: EditorContext) -> AnyView {
        AnyView(TextOptionsRow(session: editing, editor: editor))
    }

    func makeOverlay(for page: PageContext, in editor: EditorContext) -> AnyView? {
        AnyView(TextToolOverlay(page: page, editor: editor, host: host, session: editing))
    }
}

@MainActor
enum TextEditing {
    /// Writes the edit. A failure is shown and the edit stays open so the typed text can be saved again.
    @discardableResult
    static func commit(_ session: TextEditSession, editor: EditorContext) -> Bool {
        guard session.isEditing else { return true }
        do {
            try session.commit()
            return true
        } catch {
            ElementErrors.report(error, editor: editor)
            return false
        }
    }
}
