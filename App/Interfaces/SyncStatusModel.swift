import Foundation
import Observation

/// Updated by the Sync feature, shown in Settings.
@MainActor @Observable
final class SyncStatusModel {
    enum State: Equatable, Sendable {
        case idle, syncing, offline, signedOut, quotaExceeded
        case error(String)
    }

    var state: State = .idle
    var lastSyncDate: Date?
    var isSyncEnabled = true

    init() {}
}
