import SwiftUI
import UIKit

/// A window that only reacts to touches inside `interactiveFrame` (the floating panel), so the notebook underneath
/// stays usable. SwiftUI hosting views report themselves as the hit view, so the panel's frame is tracked explicitly.
final class PassthroughWindow: UIWindow {
    var interactiveFrame: CGRect = .zero

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard interactiveFrame.contains(point) else { return nil }
        return super.hitTest(point, with: event)
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
        let panel = PassthroughWindow(windowScene: scene)
        let content = ZoomPanelHost(controller: controller,
                                    onFrame: { [weak panel] in panel?.interactiveFrame = $0 },
                                    onClose: { [weak self] in self?.close(notebookID: notebookID) })
        let host = UIHostingController(rootView: content)
        host.view.backgroundColor = .clear
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
    let onFrame: (CGRect) -> Void
    let onClose: () -> Void

    var body: some View {
        VStack {
            Spacer()
            ZoomPanelView(controller: controller, onClose: onClose)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { onFrame($0) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
