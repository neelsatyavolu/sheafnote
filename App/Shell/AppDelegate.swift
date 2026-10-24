import OSLog
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    private static let log = Logger(subsystem: "co.xanom.sheafnote", category: "app")

    /// Set by the Sync feature to receive CloudKit pushes.
    @MainActor static var remoteNotificationHandler: (@MainActor ([AnyHashable: Any]) async -> UIBackgroundFetchResult)?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        if !UserDefaults.standard.bool(forKey: "UITestMode") { application.registerForRemoteNotifications() }
        return true
    }

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        if connectingSceneSession.role == .windowExternalDisplayNonInteractive {
            config.delegateClass = PresentationSceneDelegate.self
        }
        return config
    }

    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any]) async -> UIBackgroundFetchResult {
        guard let handler = Self.remoteNotificationHandler else { return .noData }
        return await handler(userInfo)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Self.log.error("Remote notification registration failed: \(error.localizedDescription, privacy: .public)")
    }
}
