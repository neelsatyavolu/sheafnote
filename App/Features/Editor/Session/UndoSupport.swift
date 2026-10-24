import Foundation

extension UndoManager {
    /// Registers an undo whose body runs on the main actor. Undo managers in the editor are only used from the
    /// main thread, so `assumeIsolated` is safe.
    func registerMain<T: AnyObject>(target: T, name: String? = nil, _ action: @escaping @MainActor (T) -> Void) {
        registerUndo(withTarget: target) { t in
            MainActor.assumeIsolated { action(t) }
        }
        if let name, !isUndoing, !isRedoing { setActionName(name) }
    }
}

/// Notifications other units can observe (audio timeline capture, search indexing).
enum EditorNotifications {
    /// Posted after a page's ink changed. `object` is the page id (`UUID`).
    static let inkDidChange = Notification.Name("co.xanom.sheafnote.editor.inkDidChange")
}
