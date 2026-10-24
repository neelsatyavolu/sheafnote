import Foundation

/// How long the app (and notebooks unlocked this session) stay open after leaving the foreground.
public enum LockGrace: String, Codable, CaseIterable, Sendable {
    case immediately, oneMinute, fiveMinutes, fifteenMinutes

    public var seconds: TimeInterval {
        switch self {
        case .immediately: 0
        case .oneMinute: 60
        case .fiveMinutes: 300
        case .fifteenMinutes: 900
        }
    }
}

/// Device-local lock preferences (stored in UserDefaults, never synced: each device chooses its own).
public struct LockSettings: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var grace: LockGrace

    public init(isEnabled: Bool = false, grace: LockGrace = .oneMinute) {
        self.isEnabled = isEnabled
        self.grace = grace
    }
}

/// Pure lock state machine. The app layer feeds it scene events and the result of device authentication;
/// it decides when the app and individual notebooks need unlocking. It never touches notebook data.
public struct AppLockState: Equatable, Sendable {
    public private(set) var settings: LockSettings
    public private(set) var isAppLocked: Bool
    public private(set) var unlockedNotebooks: Set<UUID> = []
    private var activeScenes: Set<UUID> = []
    private var backgroundedAt: Date?

    public init(settings: LockSettings) {
        self.settings = settings
        self.isAppLocked = settings.isEnabled
    }

    /// True when the privacy cover should hide content while the app is not active (app switcher snapshot).
    public var needsPrivacyCover: Bool { settings.isEnabled || !unlockedNotebooks.isEmpty }

    public func requiresUnlock(notebookID: UUID, isLocked: Bool) -> Bool {
        isLocked && !unlockedNotebooks.contains(notebookID)
    }

    public mutating func apply(_ new: LockSettings) {
        settings = new
        if !new.isEnabled { isAppLocked = false }
    }

    public mutating func unlockApp() { isAppLocked = false }

    public mutating func lockApp() { if settings.isEnabled { isAppLocked = true } }

    public mutating func unlockNotebook(_ id: UUID) { unlockedNotebooks.insert(id) }

    public mutating func relockNotebooks() { unlockedNotebooks.removeAll() }

    public mutating func sceneDidBackground(_ id: UUID, now: Date) {
        guard activeScenes.remove(id) != nil else { return }
        if activeScenes.isEmpty { backgroundedAt = now }
    }

    public mutating func sceneBecameActive(_ id: UUID, now: Date) {
        if activeScenes.isEmpty, let left = backgroundedAt, now.timeIntervalSince(left) >= settings.grace.seconds {
            lockApp()
            relockNotebooks()
        }
        backgroundedAt = nil
        activeScenes.insert(id)
    }
}
