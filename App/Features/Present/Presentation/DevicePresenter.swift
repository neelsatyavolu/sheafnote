import SwiftUI
import UIKit

/// Full-screen presenter on this device: the page alone, a laser under the finger, and a small control strip.
/// Shown when no display is connected, or when "Hide toolbars" is on while mirroring to a display.
@MainActor
final class DevicePresenter {
    static let shared = DevicePresenter()

    private weak var presented: UIViewController?

    func present(controller: PresentationController) {
        guard presented == nil, let top = Self.topViewController() else { return }
        let host = UIHostingController(rootView: DevicePresenterView(controller: controller))
        host.modalPresentationStyle = .fullScreen
        host.modalTransitionStyle = .crossDissolve
        presented = host
        top.present(host, animated: true)
    }

    func dismiss() {
        guard let presented else { return }
        presented.dismiss(animated: true)
        self.presented = nil
    }

    private static func topViewController() -> UIViewController? {
        guard let scene = ZoomPanelPresenter.activeWindowScene() else { return nil }
        let window = scene.windows.first { $0.isKeyWindow } ?? scene.windows.first { $0.windowLevel == .normal }
        var top = window?.rootViewController
        while let next = top?.presentedViewController, !next.isBeingDismissed { top = next }
        return top
    }
}

struct DevicePresenterView: View {
    let controller: PresentationController

    var body: some View {
        ZStack {
            PresentationPageView(controller: controller, showsLaser: true,
                                 showsZoomWindow: controller.options.showZoomWindow && controller.hasExternalDisplay,
                                 onLaserTouch: moveLaser)
            VStack {
                HStack {
                    Button { controller.stop() } label: {
                        Label { Text("Stop Presenting", tableName: "Present") } icon: { Image(systemName: "xmark") }
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .glassEffect(.regular.interactive(), in: Capsule())
                    }
                    .accessibilityIdentifier("present.presenter.close")
                    Spacer()
                }
                Spacer()
                pageControls
            }
            .padding(20)
        }
        .statusBarHidden()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("present.presenter")
    }

    @ViewBuilder
    private var pageControls: some View {
        if let session = controller.currentEditor as? NotebookSession, session.pageIDs.count > 1 {
            HStack(spacing: 18) {
                Button { step(-1, in: session) } label: { Image(systemName: "chevron.left").frame(width: 36, height: 36) }
                    .accessibilityLabel(Text("Previous page", tableName: "Present"))
                    .accessibilityIdentifier("present.presenter.previous")
                    .disabled(session.currentPageNumber <= 1)
                Text("\(session.currentPageNumber) / \(session.pageIDs.count)")
                    .font(.footnote.monospacedDigit().weight(.medium))
                    .accessibilityHidden(true)
                Button { step(1, in: session) } label: { Image(systemName: "chevron.right").frame(width: 36, height: 36) }
                    .accessibilityLabel(Text("Next page", tableName: "Present"))
                    .accessibilityIdentifier("present.presenter.next")
                    .disabled(session.currentPageNumber >= session.pageIDs.count)
            }
            .padding(.horizontal, 16).padding(.vertical, 6)
            .glassEffect(.regular.interactive(), in: Capsule())
        }
    }

    private func step(_ delta: Int, in session: NotebookSession) {
        let index = session.currentPageNumber - 1 + delta
        guard session.pageIDs.indices.contains(index) else { return }
        session.goToPage(id: session.pageIDs[index], animated: false)
    }

    private func moveLaser(_ point: CGPoint?, scale: CGFloat) {
        guard let laser = controller.laser else { return }
        if let point, let pageID = controller.mirror.pageID {
            laser.touchMoved(on: pageID, at: point, zoomScale: scale)
        } else {
            laser.touchEnded()
        }
    }
}
