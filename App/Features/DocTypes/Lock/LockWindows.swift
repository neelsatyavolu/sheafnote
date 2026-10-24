import Observation
import SwiftUI
import UIKit

/// One overlay `UIWindow` per window scene, above everything the scene shows (editors are full-screen covers, which a
/// view-level overlay could not hide). It is visible while the app is locked, and as a privacy cover whenever the
/// scene is not active and a lock is in use, so the app switcher snapshot never shows notes.
@MainActor
final class LockWindows {
    static let shared = LockWindows()

    private struct Entry {
        let id: UUID
        let window: UIWindow
    }

    private var entries: [ObjectIdentifier: Entry] = [:]
    private var observers: [NSObjectProtocol] = []
    private var tracking = false
    /// Scenes that are leaving or have left the foreground. `willDeactivate` fires while `activationState` still reads
    /// active, and that is exactly when the app switcher takes its snapshot, so the notifications decide, not the state.
    private var inactive: Set<ObjectIdentifier> = []

    func install(for scene: UIWindowScene) {
        guard scene.session.role == .windowApplication, entries[ObjectIdentifier(scene)] == nil else { return }
        let window = UIWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        window.backgroundColor = .clear
        let host = UIHostingController(rootView: LockOverlayRoot(controller: AppLockController.shared))
        host.view.backgroundColor = .clear
        window.rootViewController = host
        window.isHidden = true
        let id = UUID()
        entries[ObjectIdentifier(scene)] = Entry(id: id, window: window)
        if scene.activationState == .foregroundActive {
            AppLockController.shared.sceneBecameActive(id)
        } else {
            inactive.insert(ObjectIdentifier(scene))
        }
        listen()
        startTracking()
        refresh()
    }

    private func listen() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        let names: [Notification.Name] = [UIScene.didActivateNotification, UIScene.willDeactivateNotification,
                                          UIScene.didEnterBackgroundNotification, UIScene.didDisconnectNotification]
        observers = names.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let scene = note.object as? UIWindowScene else { return }
                MainActor.assumeIsolated { self?.handle(name, scene: scene) }
            }
        }
    }

    private func handle(_ name: Notification.Name, scene: UIWindowScene) {
        guard let entry = entries[ObjectIdentifier(scene)] else { return }
        let controller = AppLockController.shared
        let key = ObjectIdentifier(scene)
        switch name {
        case UIScene.didActivateNotification:
            inactive.remove(key)
            controller.sceneBecameActive(entry.id)
        case UIScene.willDeactivateNotification:
            inactive.insert(key)
        case UIScene.didEnterBackgroundNotification:
            inactive.insert(key)
            controller.sceneDidBackground(entry.id)
        case UIScene.didDisconnectNotification:
            controller.sceneDidBackground(entry.id)
            entry.window.isHidden = true
            entries[key] = nil
            inactive.remove(key)
        default: break
        }
        refresh()
    }

    /// Re-run whenever the lock state changes.
    private func startTracking() {
        guard !tracking else { return }
        tracking = true
        observeState()
    }

    private func observeState() {
        withObservationTracking {
            _ = AppLockController.shared.state
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.refresh()
                self?.observeState()
            }
        }
    }

    func refresh() {
        let state = AppLockController.shared.state
        for (key, entry) in entries {
            guard let scene = entry.window.windowScene else { entries[key] = nil; continue }
            let show = state.isAppLocked || (state.needsPrivacyCover && inactive.contains(key))
            setVisible(show, entry.window, scene: scene)
        }
    }

    private func setVisible(_ show: Bool, _ window: UIWindow, scene: UIWindowScene) {
        guard window.isHidden == show else { return }
        window.isHidden = !show
        if show {
            scene.windows.first { $0 !== window && $0.isKeyWindow }?.endEditing(true)
            window.makeKey()
        } else {
            scene.windows.first { $0 !== window && $0.windowLevel == .normal }?.makeKey()
        }
    }
}
