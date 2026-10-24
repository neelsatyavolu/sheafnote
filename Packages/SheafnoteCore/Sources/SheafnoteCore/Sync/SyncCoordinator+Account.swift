import Foundation

/// Account changes. Nothing here deletes local notebooks or ink.
extension SyncCoordinator {
    public func handle(_ event: AccountEvent) async {
        switch event {
        case .signedOut:
            // Local data stays. The engine stops until an account is available again.
            transport.stop()
            status = .signedOut
        case .signedIn:
            state.needsFullUpload = true
            persist()
            await syncNow()
        case .switched:
            // The old account's engine state and queued deletions do not apply to the new account.
            transport.stop()
            await transport.resetState()
            state.pendingDeletions = []
            state.needsFullUpload = true
            state.awaitingAccountDecision = true
            persist()
            status = .idle
        }
    }

    /// The user's answer to "Upload this device's notebooks to the new iCloud account?".
    /// Yes uploads everything. No switches to local-only mode. Either way, nothing is deleted.
    public func resolveAccountSwitch(upload: Bool) async {
        state.awaitingAccountDecision = false
        if upload {
            state.isEnabled = true
            persist()
            await syncNow()
        } else {
            state.isEnabled = false
            persist()
            transport.stop()
            status = .localOnly
        }
    }
}
