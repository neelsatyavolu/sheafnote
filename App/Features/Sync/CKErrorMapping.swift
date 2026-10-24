import CloudKit
import SheafnoteCore

/// CloudKit errors -> `SyncFailure`, the only error vocabulary the sync logic knows.
enum CKErrorMapping {
    static func failure(from error: any Error) -> SyncFailure {
        if let failure = error as? SyncFailure { return failure }
        guard let ck = error as? CKError else { return .other(error.localizedDescription) }
        switch ck.code {
        case .networkUnavailable, .networkFailure, .serverResponseLost:
            return .offline
        case .notAuthenticated, .accountTemporarilyUnavailable, .managedAccountRestricted:
            return .notAuthenticated
        case .quotaExceeded:
            return .quotaExceeded
        case .zoneNotFound, .userDeletedZone:
            return .zoneNotFound
        case .requestRateLimited, .zoneBusy, .serviceUnavailable:
            return .rateLimited(retryAfter: ck.retryAfterSeconds)
        default:
            return .other("iCloud reported a problem: \(ck.localizedDescription)")
        }
    }

    static func accountStatus(_ status: CKAccountStatus) -> AccountStatus {
        switch status {
        case .available: .available
        case .noAccount: .noAccount
        case .restricted: .restricted
        case .couldNotDetermine, .temporarilyUnavailable: .unknown
        @unknown default: .unknown
        }
    }

    /// Result of one failed record save inside a send.
    static func outcome(forFailedSave record: CKRecord, error: CKError, sent: SyncRecord) -> SendOutcome {
        switch error.code {
        case .serverRecordChanged:
            guard let serverRecord = error.serverRecord else {
                return .failed(sent.key, .other("iCloud reported a conflict without the newer version."))
            }
            do {
                guard let server = try CKRecordBridge.syncRecord(from: serverRecord) else {
                    return .failed(sent.key, .other("iCloud returned a record Sheafnote cannot read."))
                }
                return .conflict(sent: sent, server: server)
            } catch {
                return .failed(sent.key, .other(error.localizedDescription))
            }
        case .unknownItem:
            return .missingOnServer(sent: sent)
        default:
            return .failed(sent.key, failure(from: error))
        }
    }
}
