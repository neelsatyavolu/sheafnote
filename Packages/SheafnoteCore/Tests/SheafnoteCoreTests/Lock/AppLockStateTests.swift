import Foundation
import Testing
@testable import SheafnoteCore

@Suite struct AppLockStateTests {
    let t0 = Date(timeIntervalSince1970: 1_000)
    let scene = UUID()

    func state(enabled: Bool, grace: LockGrace = .oneMinute) -> AppLockState {
        AppLockState(settings: LockSettings(isEnabled: enabled, grace: grace))
    }

    @Test func startsLockedOnlyWhenEnabled() {
        #expect(state(enabled: true).isAppLocked)
        #expect(!state(enabled: false).isAppLocked)
    }

    @Test func unlockClearsAppLock() {
        var s = state(enabled: true)
        s.unlockApp()
        #expect(!s.isAppLocked)
    }

    @Test func relocksAfterGracePeriod() {
        var s = state(enabled: true, grace: .oneMinute)
        s.sceneBecameActive(scene, now: t0)
        s.unlockApp()
        s.sceneDidBackground(scene, now: t0)
        s.sceneBecameActive(scene, now: t0.addingTimeInterval(61))
        #expect(s.isAppLocked)
    }

    @Test func staysOpenInsideGracePeriod() {
        var s = state(enabled: true, grace: .fiveMinutes)
        s.sceneBecameActive(scene, now: t0)
        s.unlockApp()
        s.sceneDidBackground(scene, now: t0)
        s.sceneBecameActive(scene, now: t0.addingTimeInterval(120))
        #expect(!s.isAppLocked)
    }

    @Test func immediateGraceLocksOnAnyReturn() {
        var s = state(enabled: true, grace: .immediately)
        s.sceneBecameActive(scene, now: t0)
        s.unlockApp()
        s.sceneDidBackground(scene, now: t0)
        s.sceneBecameActive(scene, now: t0)
        #expect(s.isAppLocked)
    }

    @Test func disabledNeverLocksTheApp() {
        var s = state(enabled: false, grace: .immediately)
        s.sceneBecameActive(scene, now: t0)
        s.sceneDidBackground(scene, now: t0)
        s.sceneBecameActive(scene, now: t0.addingTimeInterval(9999))
        #expect(!s.isAppLocked)
    }

    @Test func twoWindowsOnlyCountAsBackgroundedTogether() {
        var s = state(enabled: true, grace: .immediately)
        let other = UUID()
        s.sceneBecameActive(scene, now: t0)
        s.sceneBecameActive(other, now: t0)
        s.unlockApp()
        s.sceneDidBackground(scene, now: t0)
        s.sceneBecameActive(scene, now: t0.addingTimeInterval(10))
        #expect(!s.isAppLocked)
    }

    @Test func notebookUnlockLastsUntilTheGraceExpires() {
        var s = state(enabled: false, grace: .oneMinute)
        let id = UUID()
        s.sceneBecameActive(scene, now: t0)
        #expect(s.requiresUnlock(notebookID: id, isLocked: true))
        s.unlockNotebook(id)
        #expect(!s.requiresUnlock(notebookID: id, isLocked: true))
        #expect(!s.requiresUnlock(notebookID: id, isLocked: false))
        s.sceneDidBackground(scene, now: t0)
        s.sceneBecameActive(scene, now: t0.addingTimeInterval(30))
        #expect(!s.requiresUnlock(notebookID: id, isLocked: true))
        s.sceneDidBackground(scene, now: t0.addingTimeInterval(30))
        s.sceneBecameActive(scene, now: t0.addingTimeInterval(200))
        #expect(s.requiresUnlock(notebookID: id, isLocked: true))
    }

    @Test func relockNotebooksForgetsEveryUnlock() {
        var s = state(enabled: true)
        let id = UUID()
        s.unlockNotebook(id)
        #expect(!s.requiresUnlock(notebookID: id, isLocked: true))
        s.relockNotebooks()
        #expect(s.requiresUnlock(notebookID: id, isLocked: true))
    }

    @Test func disablingTheLockUnlocksTheApp() {
        var s = state(enabled: true)
        s.apply(LockSettings(isEnabled: false, grace: .oneMinute))
        #expect(!s.isAppLocked)
    }

    @Test func enablingDoesNotLockTheCurrentSession() {
        var s = state(enabled: false)
        s.apply(LockSettings(isEnabled: true, grace: .oneMinute))
        #expect(!s.isAppLocked)
    }

    @Test func privacyCoverFollowsLockUse() {
        var s = state(enabled: false)
        #expect(!s.needsPrivacyCover)
        s.unlockNotebook(UUID())
        #expect(s.needsPrivacyCover)
        #expect(state(enabled: true).needsPrivacyCover)
    }

    @Test func settingsCodecAndDefaults() {
        let s = LockSettings()
        #expect(!s.isEnabled)
        #expect(s.grace == .oneMinute)
        let data = JSONCoding.encode(LockSettings(isEnabled: true, grace: .fifteenMinutes))
        #expect(JSONCoding.decode(LockSettings.self, from: data)?.grace == .fifteenMinutes)
        #expect(LockGrace.immediately.seconds == 0)
        #expect(LockGrace.fifteenMinutes.seconds == 900)
    }
}
