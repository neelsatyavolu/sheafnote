import Foundation
import Testing
import SheafnoteCore
@testable import Sheafnote

@MainActor
@Suite struct AppLockControllerTests {
    func make(_ results: [AuthOutcome] = [.success], enabled: Bool = false) throws
        -> (AppLockController, ScriptedAuthenticator, AppServices) {
        let services = try AppServices.inMemory()
        if enabled { services.settings.setLocal(LockSettings(isEnabled: true, grace: .oneMinute), for: "appLock.settings") }
        let auth = ScriptedAuthenticator(results: results)
        let controller = AppLockController()
        controller.configure(settings: services.settings, authenticator: auth)
        return (controller, auth, services)
    }

    @Test func lockedAtLaunchWhenEnabledInSavedSettings() throws {
        let (controller, _, _) = try make(enabled: true)
        #expect(controller.state.isAppLocked)
    }

    @Test func notLockedByDefault() throws {
        let (controller, _, _) = try make()
        #expect(!controller.state.isAppLocked)
    }

    @Test func enablingNeedsAuthenticationAndPersists() async throws {
        let (controller, auth, services) = try make()
        let error = await controller.setEnabled(true)
        #expect(error == nil)
        #expect(auth.prompts == 1)
        #expect(controller.settings.isEnabled)
        #expect(services.settings.local("appLock.settings", as: LockSettings.self)?.isEnabled == true)
        #expect(!controller.state.isAppLocked, "enabling does not lock the session the person is in")
    }

    @Test func cancelledPromptLeavesLockUnchanged() async throws {
        let (controller, _, _) = try make([.cancelled])
        let error = await controller.setEnabled(true)
        #expect(error == nil)
        #expect(!controller.settings.isEnabled)
    }

    @Test func cannotEnableWithoutDevicePasscode() async throws {
        let (controller, auth, _) = try make()
        auth.available = false
        let error = await controller.setEnabled(true)
        #expect(error != nil)
        #expect(!controller.settings.isEnabled)
        #expect(auth.prompts == 0)
    }

    @Test func failedPromptReportsTheReason() async throws {
        let (controller, _, _) = try make([.failed("Face ID failed")])
        #expect(await controller.setEnabled(true) == "Face ID failed")
        #expect(!controller.settings.isEnabled)
    }

    @Test func disablingNeedsAuthentication() async throws {
        let (controller, auth, _) = try make(enabled: true)
        _ = await controller.setEnabled(false)
        #expect(auth.prompts == 1)
        #expect(!controller.settings.isEnabled)
        #expect(!controller.state.isAppLocked)
    }

    @Test func unlockAppSucceedsAfterAuthentication() async throws {
        let (controller, _, _) = try make(enabled: true)
        #expect(await controller.unlockApp())
        #expect(!controller.state.isAppLocked)
    }

    @Test func failedUnlockStaysLockedWithMessage() async throws {
        let (controller, _, _) = try make([.failed("nope")], enabled: true)
        #expect(await controller.unlockApp() == false)
        #expect(controller.state.isAppLocked)
        #expect(controller.message == "nope")
        #expect(!controller.canContinueWithoutAuthentication)
    }

    @Test func noPasscodeOffersToContinueWithoutLosingAnything() async throws {
        let (controller, auth, _) = try make(enabled: true)
        auth.available = false
        #expect(await controller.unlockApp() == false)
        #expect(controller.canContinueWithoutAuthentication)
        #expect(controller.message != nil)
        controller.continueWithoutAuthentication()
        #expect(!controller.state.isAppLocked)
        #expect(controller.message == nil)
    }

    @Test func continueDoesNothingUnlessThePasscodeIsMissing() async throws {
        let (controller, _, _) = try make([.failed("x")], enabled: true)
        _ = await controller.unlockApp()
        controller.continueWithoutAuthentication()
        #expect(controller.state.isAppLocked)
    }

    @Test func notebookUnlockIsTrackedPerNotebook() async throws {
        let (controller, _, services) = try make()
        let a = try DocumentCreation.make(kind: .text, title: "A", cover: "ledger", services: services, folder: nil)
        let b = try DocumentCreation.make(kind: .text, title: "B", cover: "ledger", services: services, folder: nil)
        try NotebookLockAction.setLocked(true, [a, b], services: services)
        #expect(controller.requiresUnlock(a))
        #expect(await controller.unlockNotebook(a.id))
        #expect(!controller.requiresUnlock(a))
        #expect(controller.requiresUnlock(b))
    }

    @Test func graceSettingPersists() throws {
        let (controller, _, services) = try make()
        controller.setGrace(.fifteenMinutes)
        #expect(services.settings.local("appLock.settings", as: LockSettings.self)?.grace == .fifteenMinutes)
    }

    @Test func scriptedAuthenticatorPlaysResultsInOrder() async {
        let auth = ScriptedAuthenticator(results: [.cancelled, .success])
        #expect(await auth.authenticate(reason: "x") == .cancelled)
        #expect(await auth.authenticate(reason: "x") == .success)
        #expect(await auth.authenticate(reason: "x") == .success)
    }

    @Test func systemAuthenticatorMapsLocalAuthenticationErrors() {
        func outcome(_ code: Int) -> AuthOutcome {
            SystemAuthenticator.outcome(for: NSError(domain: "com.apple.LocalAuthentication", code: code))
        }
        #expect(outcome(-2) == .cancelled)       // userCancel
        #expect(outcome(-4) == .cancelled)       // systemCancel
        #expect(outcome(-5) == .unavailable)     // passcodeNotSet
        if case .failed = outcome(-1) {} else { Issue.record("authenticationFailed should map to failed") }
        if case .failed = SystemAuthenticator.outcome(for: nil) {} else { Issue.record("nil should map to failed") }
    }
}
