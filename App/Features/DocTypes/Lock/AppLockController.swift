import Foundation
import Observation
import OSLog
import SheafnoteCore

/// Owns the lock state for the whole process (every window shares it) and talks to the device authenticator.
/// It never reads or changes notebook content: locking only decides which screens may be shown.
@MainActor @Observable
final class AppLockController {
    static let shared = AppLockController()
    private static let settingsKey = "appLock.settings"
    private static let log = Logger(subsystem: "co.xanom.sheafnote", category: "lock")

    private(set) var state = AppLockState(settings: LockSettings())
    /// Message from the last failed attempt, shown on the lock screen.
    private(set) var message: String?
    /// True after iOS reported that no device passcode is set: the lock can't verify anyone, so the person may continue.
    private(set) var canContinueWithoutAuthentication = false
    private(set) var isAuthenticating = false

    @ObservationIgnored private var authenticator: any DeviceAuthenticating = SystemAuthenticator()
    @ObservationIgnored private var store: AppSettingsStore?

    var settings: LockSettings { state.settings }

    /// Called once at launch. Loads the device's lock settings, so a locked app starts locked.
    func configure(settings store: AppSettingsStore, authenticator: any DeviceAuthenticating) {
        self.store = store
        self.authenticator = authenticator
        let saved = store.local(Self.settingsKey, as: LockSettings.self) ?? LockSettings()
        state = AppLockState(settings: saved)
    }

    // MARK: Scene events

    func sceneBecameActive(_ id: UUID, now: Date = .now) { state.sceneBecameActive(id, now: now) }
    func sceneDidBackground(_ id: UUID, now: Date = .now) { state.sceneDidBackground(id, now: now) }

    // MARK: Unlocking

    /// Asks iOS to verify the person, then opens the app. Returns whether the app is now unlocked.
    @discardableResult
    func unlockApp() async -> Bool {
        guard state.isAppLocked else { return true }
        let ok = await verify(reason: String(localized: "Unlock Sheafnote", table: "DocTypes"))
        if ok { state.unlockApp() }
        return ok
    }

    @discardableResult
    func unlockNotebook(_ id: UUID) async -> Bool {
        let ok = await verify(reason: String(localized: "Open this locked notebook", table: "DocTypes"))
        if ok { state.unlockNotebook(id) }
        return ok
    }

    /// The person chose to continue because the device has no passcode (see `canContinueWithoutAuthentication`).
    func continueWithoutAuthentication(notebookID: UUID? = nil) {
        guard canContinueWithoutAuthentication else { return }
        if let notebookID { state.unlockNotebook(notebookID) } else { state.unlockApp() }
        clearMessage()
    }

    func clearMessage() {
        message = nil
        canContinueWithoutAuthentication = false
    }

    private func verify(reason: String) async -> Bool {
        guard !isAuthenticating else { return false }
        isAuthenticating = true
        defer { isAuthenticating = false }
        clearMessage()
        switch await authenticator.authenticate(reason: reason) {
        case .success:
            return true
        case .cancelled:
            return false
        case .unavailable:
            message = String(localized: "This device has no passcode, so Sheafnote can't check who is opening it. Set a passcode in the iOS Settings app to use locks.", table: "DocTypes")
            canContinueWithoutAuthentication = true
            return false
        case .failed(let reason):
            Self.log.error("Authentication failed: \(reason, privacy: .public)")
            message = reason
            return false
        }
    }

    // MARK: Settings

    /// Turning the lock on or off asks for authentication first, so nobody can be locked out by a mistake
    /// and nobody else can switch it off. Returns an error message to show, or nil on success.
    func setEnabled(_ enabled: Bool) async -> String? {
        guard enabled != settings.isEnabled else { return nil }
        if enabled, !authenticator.canAuthenticate() {
            return String(localized: "Set a passcode in the iOS Settings app first. App lock uses your device passcode, Face ID or Touch ID.", table: "DocTypes")
        }
        let reason = enabled ? String(localized: "Turn on app lock", table: "DocTypes")
                             : String(localized: "Turn off app lock", table: "DocTypes")
        switch await authenticator.authenticate(reason: reason) {
        case .success:
            save(LockSettings(isEnabled: enabled, grace: settings.grace))
            return nil
        case .cancelled:
            return nil
        case .unavailable:
            guard !enabled else { return String(localized: "Set a passcode in the iOS Settings app first.", table: "DocTypes") }
            save(LockSettings(isEnabled: false, grace: settings.grace))
            return nil
        case .failed(let reason):
            return reason
        }
    }

    func setGrace(_ grace: LockGrace) {
        save(LockSettings(isEnabled: settings.isEnabled, grace: grace))
    }

    private func save(_ new: LockSettings) {
        state.apply(new)
        store?.setLocal(new, for: Self.settingsKey)
    }

    // MARK: Per-notebook lock

    func requiresUnlock(_ notebook: Notebook) -> Bool {
        state.requiresUnlock(notebookID: notebook.id, isLocked: notebook.isLocked)
    }
}
