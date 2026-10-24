import SwiftUI
import UIKit

/// Scene delegate for the external display (AirPlay / HDMI). Stub: shows a black screen until the present unit lands.
final class PresentationSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        let host = UIHostingController(rootView: Color.black.ignoresSafeArea())
        window.rootViewController = host
        window.isHidden = false
        self.window = window
    }
}
