import Foundation
import SheafnoteCore

/// Drops a selection whose ink or elements are gone. Undo and redo can remove what is selected (or bring back
/// differently identified ink), and a frame with handles around nothing would offer actions on things that do not exist.
@MainActor
final class SelectionPruner {
    private var tokens: [NSObjectProtocol] = []
    private weak var editor: (any EditorContext)?

    func start(editor: any EditorContext) {
        stop()
        self.editor = editor
        for name in [Notification.Name.NSUndoManagerDidUndoChange, .NSUndoManagerDidRedoChange] {
            tokens.append(NotificationCenter.default.addObserver(forName: name, object: editor.undoManager, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { if let editor = self?.editor { Self.prune(editor) } }
            })
        }
    }

    func stop() {
        tokens.forEach { NotificationCenter.default.removeObserver($0) }
        tokens = []
    }

    static func prune(_ editor: any EditorContext) {
        let selection = editor.selection
        guard !selection.isEmpty, let pageID = selection.pageID else { return }
        let page = editor.visiblePages.first { $0.pageID == pageID } ?? editor.currentPage.flatMap { $0.pageID == pageID ? $0 : nil }
        guard let page else { return }
        let strokes = Set(page.ink.strokes.map(\.id)), elements = Set(page.elements.all.map(\.id))
        if selection.strokeIDs.isSubset(of: strokes), selection.elementIDs.isSubset(of: elements) { return }
        selection.clear()
    }
}
