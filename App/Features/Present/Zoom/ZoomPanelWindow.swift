import SwiftUI
import UIKit

/// A window that only reacts to touches that land on its content, so the notebook underneath stays usable.
final class PassthroughWindow: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        return hit === rootViewController?.view ? nil : hit
    }
}

/// Floats the zoom strip over the bottom of the notebook in its own window, outside the options row's scroll view, so
/// horizontal writing is never mistaken for scrolling.
@MainActor
final class ZoomPanelPresenter {
    static let shared = ZoomPanelPresenter()

    private var window: PassthroughWindow?
    private var shownFor: UUID?

    var isShown: Bool { window != nil }

    func show(controller: ZoomWindowController, notebookID: UUID) {
        if shownFor == notebookID, window != nil { return }
        hide()
        guard let scene = Self.activeWindowScene() else { return }
        let content = ZoomPanelHost(controller: controller) { [weak self] in self?.close(notebookID: notebookID) }
        let host = UIHostingController(rootView: content)
        host.view.backgroundColor = .clear
        let panel = PassthroughWindow(windowScene: scene)
        panel.windowLevel = .normal + 1
        panel.backgroundColor = .clear
        panel.rootViewController = host
        panel.isHidden = false
        window = panel
        shownFor = notebookID
    }

    func hide() {
        window?.isHidden = true
        window = nil
        shownFor = nil
    }

    private func close(notebookID: UUID) {
        guard let editor = ZoomWindowController.existing(for: notebookID)?.editor else { return hide() }
        // Leaving the zoom tool hides the panel (via the tool's `deactivate`).
        editor.toolState.select(editor.toolState.previousToolID == .zoomWindow ? .pen : editor.toolState.previousToolID)
    }

    static func activeWindowScene() -> UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let app = scenes.filter { $0.session.role == .windowApplication }
        return app.first { $0.activationState == .foregroundActive } ?? app.first
    }
}

private struct ZoomPanelHost: View {
    let controller: ZoomWindowController
    let onClose: () -> Void

    var body: some View {
        VStack {
            Spacer()
            ZoomPanelView(controller: controller, onClose: onClose)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
