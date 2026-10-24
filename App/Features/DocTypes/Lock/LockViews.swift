import SwiftUI

/// Full-screen lock: shown above every window of the app (including editors) while the app is locked.
struct AppLockScreen: View {
    let controller: AppLockController

    var body: some View {
        LockPanel(
            title: Text("Sheafnote is Locked", tableName: "DocTypes"),
            controller: controller,
            unlock: { Task { await controller.unlockApp() } },
            continueAnyway: { controller.continueWithoutAuthentication() },
            secondary: nil)
            .accessibilityIdentifier("lock.screen")
            .task { await controller.unlockApp() }
    }
}

/// Shared look of the app lock and the locked-notebook screen.
struct LockPanel: View {
    let title: Text
    let controller: AppLockController
    let unlock: () -> Void
    let continueAnyway: () -> Void
    let secondary: AnyView?

    var body: some View {
        ZStack {
            Rectangle().fill(.background).ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 44, weight: .regular))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                title.font(.title2.weight(.semibold)).multilineTextAlignment(.center)
                if let message = controller.message {
                    Text(message)
                        .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        .accessibilityIdentifier("lock.message")
                }
                Button(action: unlock) {
                    Label { Text("Unlock", tableName: "DocTypes") } icon: { Image(systemName: "faceid") }
                        .frame(minWidth: 160)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(controller.isAuthenticating)
                .accessibilityLabel(Text("Unlock with Face ID, Touch ID or passcode", tableName: "DocTypes"))
                .accessibilityIdentifier("lock.unlock")
                if controller.canContinueWithoutAuthentication {
                    Button(action: continueAnyway) { Text("Continue Without Lock", tableName: "DocTypes") }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("lock.continue")
                }
                if let secondary { secondary }
            }
            .padding(32)
            .frame(maxWidth: 420)
        }
        .accessibilityElement(children: .contain)
    }
}

/// Hides content in the app switcher snapshot and while the app is not active.
struct PrivacyCover: View {
    var body: some View {
        ZStack {
            Rectangle().fill(.regularMaterial)
            Color(.systemBackground).opacity(0.55)
            Image(systemName: "lock.fill")
                .font(.system(size: 40)).foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .ignoresSafeArea()
        .accessibilityIdentifier("lock.privacyCover")
    }
}

/// The overlay window's content: the lock screen while locked, else the privacy cover.
struct LockOverlayRoot: View {
    let controller: AppLockController

    var body: some View {
        if controller.state.isAppLocked {
            AppLockScreen(controller: controller)
        } else {
            PrivacyCover()
        }
    }
}

/// Stand-in drawn inside the view tree so a locked app never shows content, even before the overlay window exists.
private struct LockedBackdrop: View {
    var body: some View {
        Rectangle().fill(.background).ignoresSafeArea()
    }
}

private struct AppLockCoverModifier: ViewModifier {
    @State private var controller = AppLockController.shared

    func body(content: Content) -> some View {
        content
            .accessibilityHidden(controller.state.isAppLocked)
            .overlay { if controller.state.isAppLocked { LockedBackdrop() } }
            .background(LockSceneAnchor())
    }
}

extension View {
    /// Wraps the app's root in the lock: installs this window's lock overlay and keeps content hidden while locked.
    func appLockCover() -> some View { modifier(AppLockCoverModifier()) }
}

/// Finds the window scene this view lives in and gives it a lock overlay window.
private struct LockSceneAnchor: UIViewRepresentable {
    func makeUIView(context: Context) -> AnchorView { AnchorView() }
    func updateUIView(_ uiView: AnchorView, context: Context) {}

    final class AnchorView: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            if let scene = window?.windowScene { LockWindows.shared.install(for: scene) }
        }
    }
}
