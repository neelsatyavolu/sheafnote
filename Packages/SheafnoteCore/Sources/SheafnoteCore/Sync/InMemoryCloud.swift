import Foundation

/// A fake private CloudKit database for tests and previews. Mimics `.ifServerRecordUnchanged` saves:
/// a save based on a stale version comes back as a conflict carrying the server's record.
@MainActor
public final class InMemoryCloud {
    private struct LogEntry { var seq: Int; var key: RecordKey; var deleted: Bool }

    private var stored: [RecordKey: SyncRecord] = [:]
    private var log: [LogEntry] = []
    private var counter = 0
    public private(set) var zoneExists = false
    /// Bumped each time the zone is deleted, so devices can tell their zone vanished.
    public private(set) var zoneGeneration = 0

    public init() {}

    public var records: [SyncRecord] { Array(stored.values) }
    public func record(_ key: RecordKey) -> SyncRecord? { stored[key] }
    public var latestSeq: Int { counter }

    public func createZone() { zoneExists = true }

    /// Simulates the user deleting the app's iCloud data: the zone and every record vanish.
    public func deleteZone() {
        zoneExists = false
        zoneGeneration += 1
        stored = [:]
        log = []
    }

    /// Edits a server record directly, as if another device had saved it.
    public func put(_ record: SyncRecord) -> SyncRecord {
        counter += 1
        var saved = record
        saved.changeTag = String(counter)
        saved.systemFields = Data(String(counter).utf8)
        stored[record.key] = saved
        log.append(LogEntry(seq: counter, key: record.key, deleted: false))
        return saved
    }

    func remove(_ key: RecordKey) {
        stored[key] = nil
        counter += 1
        log.append(LogEntry(seq: counter, key: key, deleted: true))
    }

    func changes(since cursor: Int) -> FetchedChanges {
        let fresh = log.filter { $0.seq > cursor }
        var latest: [RecordKey: LogEntry] = [:]
        for entry in fresh { latest[entry.key] = entry }
        let ordered = latest.values.sorted { $0.seq < $1.seq }
        return FetchedChanges(records: ordered.compactMap { $0.deleted ? nil : stored[$0.key] },
                              deletions: ordered.filter(\.deleted).map(\.key))
    }

    func save(_ sent: SyncRecord) -> SendOutcome {
        if let current = stored[sent.key] {
            guard sent.systemFields == current.systemFields else { return .conflict(sent: sent, server: current) }
        } else if sent.systemFields != nil {
            return .missingOnServer(sent: sent)
        }
        return .saved(sent: sent, saved: put(sent))
    }
}

/// One device's connection to an `InMemoryCloud`.
@MainActor
public final class InMemoryTransport: CloudTransport {
    public var onAccountEvent: (@MainActor @Sendable (AccountEvent) -> Void)?
    public var onRemoteChange: (@MainActor @Sendable () -> Void)?
    public var cloud: InMemoryCloud
    public var isOnline = true
    public var account: AccountStatus = .available
    public var quotaFull = false
    public private(set) var started = false
    public private(set) var savesSent: [RecordKey] = []
    public private(set) var deletesSent: [RecordKey] = []
    private var cursor = 0
    private var committedCursor = 0
    public private(set) var commitCount = 0
    private var knownGeneration = 0
    private var zoneWasDeleted = false
    private var hasStartedOnce = false

    public init(cloud: InMemoryCloud) { self.cloud = cloud }

    public func accountStatus() async -> AccountStatus { account }

    public func start() async throws {
        try checkReachable()
        cloud.createZone()
        if cloud.zoneGeneration != knownGeneration {
            zoneWasDeleted = hasStartedOnce
            knownGeneration = cloud.zoneGeneration
        }
        started = true
        hasStartedOnce = true
    }

    public func stop() { started = false }

    public func resetState() async {
        cursor = 0
        committedCursor = 0
        zoneWasDeleted = false
    }

    /// Points this device at another account's database (the account switch case).
    public func attach(to other: InMemoryCloud) {
        cloud = other
        knownGeneration = other.zoneGeneration
        cursor = 0
        committedCursor = 0
    }

    /// Simulates iCloud account changes the way the system reports them.
    public func simulate(_ event: AccountEvent) {
        switch event {
        case .signedOut: account = .noAccount
        case .signedIn, .switched: account = .available
        }
        onAccountEvent?(event)
    }

    /// Simulates a silent push telling the device the server changed.
    public func simulateRemoteChange() { onRemoteChange?() }

    public func fetchChanges() async throws -> FetchedChanges {
        try checkReachable()
        guard cloud.zoneExists else { throw SyncFailure.zoneNotFound }
        if zoneWasDeleted {
            zoneWasDeleted = false
            return FetchedChanges(zoneDeleted: true)
        }
        let changes = cloud.changes(since: cursor)
        cursor = cloud.latestSeq
        return changes
    }

    public func commitFetched() async {
        committedCursor = cursor
        commitCount += 1
    }

    /// Simulates quitting the app: a fetch that was never committed is forgotten and will be delivered again.
    public func simulateRelaunch() { cursor = committedCursor }

    public func send(_ changes: [OutgoingChange]) async throws -> [SendOutcome] {
        try checkReachable()
        guard cloud.zoneExists else { throw SyncFailure.zoneNotFound }
        return changes.map { change in
            switch change {
            case .save(let record):
                if quotaFull { return .failed(record.key, .quotaExceeded) }
                savesSent.append(record.key)
                return cloud.save(record)
            case .delete(let key):
                deletesSent.append(key)
                cloud.remove(key)
                return .deleted(key)
            }
        }
    }

    private func checkReachable() throws {
        guard isOnline else { throw SyncFailure.offline }
        guard account == .available else { throw SyncFailure.notAuthenticated }
    }
}
