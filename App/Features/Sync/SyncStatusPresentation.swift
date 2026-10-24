import Foundation
import SheafnoteCore

/// User-facing text and symbol for a sync status. Shared by the library indicator and the settings screen.
struct SyncStatusPresentation: Equatable {
    let title: String
    let detail: String
    let symbolName: String
    let needsAttention: Bool

    init(status: SyncStatus) {
        switch status {
        case .idle:
            self.init(String(localized: "Up to date", table: "Sync"),
                      String(localized: "Your notebooks are in sync with iCloud.", table: "Sync"),
                      "checkmark.icloud", false)
        case .syncing:
            self.init(String(localized: "Syncing", table: "Sync"),
                      String(localized: "Sheafnote is exchanging changes with iCloud.", table: "Sync"),
                      "arrow.triangle.2.circlepath.icloud", false)
        case .offline:
            self.init(String(localized: "Offline", table: "Sync"), SyncFailure.offline.userMessage, "icloud.slash", false)
        case .signedOut:
            self.init(String(localized: "Not signed in to iCloud", table: "Sync"), SyncFailure.notAuthenticated.userMessage,
                      "exclamationmark.icloud", true)
        case .quotaExceeded:
            self.init(String(localized: "iCloud storage full", table: "Sync"), SyncFailure.quotaExceeded.userMessage,
                      "exclamationmark.icloud", true)
        case .localOnly:
            self.init(String(localized: "Sync is off", table: "Sync"),
                      String(localized: "Notebooks stay on this device only.", table: "Sync"), "icloud.slash", false)
        case .error(let message):
            self.init(String(localized: "Sync problem", table: "Sync"), message, "exclamationmark.icloud", true)
        }
    }

    private init(_ title: String, _ detail: String, _ symbolName: String, _ needsAttention: Bool) {
        self.title = title
        self.detail = detail
        self.symbolName = symbolName
        self.needsAttention = needsAttention
    }
}
