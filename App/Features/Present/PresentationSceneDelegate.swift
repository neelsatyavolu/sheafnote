import SwiftUI
import UIKit

/// Scene delegate for the external display (AirPlay / HDMI). Shows the presented page alone on black, or a quiet
/// standby screen while nothing is being presented.
final class PresentationSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = UIHostingController(rootView: ExternalPresentationRoot())
        window.isHidden = false
        self.window = window
        let sceneID = session.persistentIdentifier
        Task { @MainActor in PresentationController.shared.displayConnected(sceneID: sceneID) }
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        let sceneID = scene.session.persistentIdentifier
        window = nil
        Task { @MainActor in PresentationController.shared.displayDisconnected(sceneID: sceneID) }
    }
}

/// What the audience sees on the external display.
struct ExternalPresentationRoot: View {
    var body: some View {
        let controller = PresentationController.shared
        let machine = controller.machine
        if machine.externalShowsPage {
            PresentationPageView(controller: controller, showsLaser: machine.externalShowsLaser,
                                 showsZoomWindow: machine.externalShowsZoomWindow)
        } else {
            ZStack {
                Color.black
                Text("Sheafnote")
                    .font(.system(size: 28, weight: .light, design: .serif))
                    .foregroundStyle(.white.opacity(0.25))
            }
            .ignoresSafeArea()
        }
    }
}
