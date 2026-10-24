import Foundation

public enum OutgoingChange: Sendable {
    case save(SyncRecord)
    case delete(RecordKey)
}

/// Why a send or fetch failed, independent of CloudKit's error types.
public enum SyncFailure: Error, Equatable, Sendable {
    case offline
    case quotaExceeded
    case notAuthenticated
    case zoneNotFound
    /// CloudKit asked us to slow down.
    case rateLimited(retryAfter: TimeInterval?)
    case other(String)

    public var userMessage: String {
        switch self {
        case .offline: "You're offline. Sheafnote will sync when a connection returns."
        case .quotaExceeded: "Your iCloud storage is full. Free up space or buy more storage to keep syncing."
        case .notAuthenticated: "Sign in to iCloud in Settings to sync your notebooks."
        case .zoneNotFound: "Sheafnote's iCloud data could not be found and will be uploaded again."
        case .rateLimited: "iCloud is busy. Sheafnote will try again shortly."
        case .other(let message): message
        }
    }
}

public enum SendOutcome: Sendable {
    case saved(sent: SyncRecord, saved: SyncRecord)
    case deleted(RecordKey)
    /// The server holds a different version than the one our save was based on.
    case conflict(sent: SyncRecord, server: SyncRecord)
    /// We saved over a server version that no longer exists (deleted elsewhere). Upload it again as new.
    case missingOnServer(sent: SyncRecord)
    case failed(RecordKey, SyncFailure)
}

public struct FetchedChanges: Sendable {
    public var records: [SyncRecord]
    public var deletions: [RecordKey]
    /// The whole zone was deleted on the server (for example the user cleared iCloud data for the app).
    public var zoneDeleted: Bool

    public init(records: [SyncRecord] = [], deletions: [RecordKey] = [], zoneDeleted: Bool = false) {
        self.records = records
        self.deletions = deletions
        self.zoneDeleted = zoneDeleted
    }
}

public enum AccountStatus: Sendable, Equatable {
    case available, noAccount, restricted, unknown
}

public enum AccountEvent: Sendable, Equatable {
    case signedIn, signedOut, switched
}

/// The only seam between sync logic and iCloud. `CKSyncEngineTransport` (app target) implements it over
/// `CKSyncEngine`; `InMemoryCloud` implements it for tests.
@MainActor
public protocol CloudTransport: AnyObject {
    /// Called when the signed-in iCloud account changes. Set by the coordinator.
    var onAccountEvent: (@MainActor @Sendable (AccountEvent) -> Void)? { get set }
    /// Called when the server pushed changes or the engine fetched on its own. The coordinator runs a cycle.
    var onRemoteChange: (@MainActor @Sendable () -> Void)? { get set }
    func accountStatus() async -> AccountStatus
    /// Creates the custom zone if needed and starts the engine.
    func start() async throws
    /// Stops the engine. Local data is untouched.
    func stop()
    /// Forgets the change token and engine state (account switch, zone recreated): the next fetch is a full one.
    func resetState() async
    func fetchChanges() async throws -> FetchedChanges
    /// Sends changes and reports a result per change. Throws for whole-request failures (offline, not signed in).
    func send(_ changes: [OutgoingChange]) async throws -> [SendOutcome]
}
