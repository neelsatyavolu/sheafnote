import SwiftUI

@main
struct SheafnoteApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView(bootstrap: AppBootstrap.shared)
        }
    }
}
