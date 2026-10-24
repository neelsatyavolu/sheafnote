import SwiftUI

/// Whiteboards, text documents and the app/notebook lock.
enum DocTypesFeature: FeatureModule {
    static let id = "doc-types"

    static func register(into host: FeatureHost) {
        configureLock(host)
        host.documents.register(WhiteboardEditorFactory())
        host.documents.register(TextDocumentEditorFactory())
        host.documents.gate = { notebook, content in
            AnyView(NotebookLockGate(notebook: notebook, content: content))
        }
        host.library.registerNewItem(DocumentCreation.whiteboardItem)
        host.library.registerNewItem(DocumentCreation.textDocumentItem)
        host.library.registerNotebookAction(NotebookLockAction.action)
        host.notebookMenu.registerMenuItem(WhiteboardMenu.showWholeBoard)
        host.settings.register(LockSettingsSection.section)
    }

    private static func configureLock(_ host: FeatureHost) {
        let authenticator: any DeviceAuthenticating = UserDefaults.standard.bool(forKey: "UITestMode")
            ? ScriptedAuthenticator(results: UserDefaults.standard.bool(forKey: "UITestAuthFails")
                ? [.failed("Authentication failed (test).")] : [.success])
            : SystemAuthenticator()
        AppLockController.shared.configure(settings: host.services.settings, authenticator: authenticator)
    }
}
