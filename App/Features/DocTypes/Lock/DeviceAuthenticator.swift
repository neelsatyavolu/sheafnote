import Foundation
import LocalAuthentication

/// Result of asking iOS to verify the person holding the device.
enum AuthOutcome: Equatable, Sendable {
    case success
    /// The person dismissed the prompt, or the system cancelled it (app moved to the background).
    case cancelled
    /// iOS cannot verify anyone on this device (no passcode set). Anyone holding the device can already open it.
    case unavailable
    case failed(String)
}

@MainActor
protocol DeviceAuthenticating: AnyObject {
    /// False when the device has no passcode, so a lock could not be satisfied.
    func canAuthenticate() -> Bool
    func authenticate(reason: String) async -> AuthOutcome
}

/// Face ID, Touch ID or the device passcode through `LocalAuthentication`.
@MainActor
final class SystemAuthenticator: DeviceAuthenticating {
    func canAuthenticate() -> Bool {
        var error: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
    }

    func authenticate(reason: String) async -> AuthOutcome {
        let context = LAContext()
        var probe: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &probe) else {
            return Self.outcome(for: probe)
        }
        do {
            let ok = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            return ok ? .success : .failed(String(localized: "Authentication did not succeed.", table: "DocTypes"))
        } catch {
            return Self.outcome(for: error as NSError)
        }
    }

    nonisolated static func outcome(for error: NSError?) -> AuthOutcome {
        guard let error else { return .failed(String(localized: "Authentication did not succeed.", table: "DocTypes")) }
        switch LAError.Code(rawValue: error.code) {
        case .userCancel, .appCancel, .systemCancel:
            return .cancelled
        case .passcodeNotSet:
            return .unavailable
        default:
            return .failed(error.localizedDescription)
        }
    }
}

/// Stands in for the system prompt in UI tests (`-UITestMode 1`): succeeds, or fails with `-UITestAuthFails 1`.
@MainActor
final class ScriptedAuthenticator: DeviceAuthenticating {
    var results: [AuthOutcome]
    private(set) var prompts = 0
    var available = true

    init(results: [AuthOutcome] = [.success]) { self.results = results }

    func canAuthenticate() -> Bool { available }

    func authenticate(reason: String) async -> AuthOutcome {
        prompts += 1
        guard available else { return .unavailable }
        return results.count > 1 ? results.removeFirst() : (results.first ?? .success)
    }
}
