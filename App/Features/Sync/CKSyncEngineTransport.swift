import CloudKit
import Foundation
import OSLog
import SheafnoteCore

/// `CloudTransport` over `CKSyncEngine` against the private database, one custom zone (`SheafnoteZone`).
///
/// The local SwiftData store is the source of truth for what is pending: for every send the coordinator hands over
/// the records, this type puts matching entries into the engine's pending list, answers the engine's batch requests
/// from them, and removes whatever is left afterwards. Engine state (change tokens, pending list) is serialized to
/// `Application Support/SheafnoteSync/state.json`.
///
/// Not exercised by automated tests: CloudKit needs a signed-in iCloud account. See README, "Sync and CloudKit".
@MainActor
final class CKSyncEngineTransport: CloudTransport {
    static let containerIdentifier = "iCloud.co.xanom.sheafnote"
    static let log = Logger(subsystem: "co.xanom.sheafnote", category: "sync")

    var onAccountEvent: (@MainActor @Sendable (AccountEvent) -> Void)?
    var onRemoteChange: (@MainActor @Sendable () -> Void)?

    private lazy var container = CKContainer(identifier: Self.containerIdentifier)
    let stateStore: EngineStateStore
    let assetDirectory: URL
    var engine: CKSyncEngine?
    var persisted: EngineStateStore.Persisted
    var buffer = EventBuffer()
    var outgoing: [CKRecord.ID: OutgoingChange] = [:]
    var tempFiles: [URL] = []
    var explicitOperations = 0

    init(stateStore: EngineStateStore, assetDirectory: URL = FileManager.default.temporaryDirectory.appending(path: "SheafnoteSyncAssets")) {
        self.stateStore = stateStore
        self.assetDirectory = assetDirectory
        do {
            self.persisted = try stateStore.load()
        } catch {
            // A damaged state file only costs a full re-fetch; local data is untouched.
            Self.log.error("Sync state unreadable, starting a full fetch: \(error.localizedDescription, privacy: .public)")
            self.persisted = EngineStateStore.Persisted()
        }
    }

    func accountStatus() async -> AccountStatus {
        do {
            return CKErrorMapping.accountStatus(try await container.accountStatus())
        } catch {
            Self.log.error("Account status failed: \(error.localizedDescription, privacy: .public)")
            return .unknown
        }
    }

    func start() async throws {
        if engine == nil {
            var configuration = CKSyncEngine.Configuration(database: container.privateCloudDatabase,
                                                           stateSerialization: persisted.serialization, delegate: self)
            configuration.automaticallySync = true
            engine = CKSyncEngine(configuration)
        }
        guard let engine else { return }
        if !persisted.zoneCreated {
            engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: CKRecordBridge.zoneID))])
            try await perform { try await engine.sendChanges() }
            try throwBufferedError()
            guard persisted.zoneCreated else { throw SyncFailure.zoneNotFound }
        }
    }

    func stop() {
        engine = nil
    }

    func resetState() async {
        engine = nil
        buffer = EventBuffer()
        persisted = EngineStateStore.Persisted()
        do { try stateStore.save(persisted) } catch {
            Self.log.error("Could not clear sync state: \(error.localizedDescription, privacy: .public)")
        }
    }

    func fetchChanges() async throws -> FetchedChanges {
        guard let engine else { throw SyncFailure.other("Sync has not started.") }
        try throwBufferedError()
        try await perform { try await engine.fetchChanges() }
        let changes = FetchedChanges(records: buffer.records, deletions: buffer.deletions, zoneDeleted: buffer.zoneDeleted)
        buffer.clearFetched()
        try throwBufferedError()
        return changes
    }

    func send(_ changes: [OutgoingChange]) async throws -> [SendOutcome] {
        guard let engine else { throw SyncFailure.other("Sync has not started.") }
        var pending: [CKSyncEngine.PendingRecordZoneChange] = []
        outgoing = [:]
        buffer.sent = []
        for change in changes {
            switch change {
            case .save(let record):
                let id = CKRecordBridge.recordID(for: record.key)
                outgoing[id] = change
                pending.append(.saveRecord(id))
            case .delete(let key):
                let id = CKRecordBridge.recordID(for: key)
                outgoing[id] = change
                pending.append(.deleteRecord(id))
            }
        }
        engine.state.add(pendingRecordZoneChanges: pending)
        defer { cleanUpAfterSend(pending, engine: engine) }
        try await perform { try await engine.sendChanges() }
        try throwBufferedError()
        return outcomes(for: changes)
    }

    /// Runs an engine operation, counting it as explicit so its events are not mistaken for a server push,
    /// and translating CloudKit errors.
    private func perform(_ operation: () async throws -> Void) async throws {
        explicitOperations += 1
        defer { explicitOperations -= 1 }
        do { try await operation() } catch { throw CKErrorMapping.failure(from: error) }
    }

    func throwBufferedError() throws {
        guard let error = buffer.error else { return }
        buffer.error = nil
        throw CKErrorMapping.failure(from: error)
    }

    private func cleanUpAfterSend(_ pending: [CKSyncEngine.PendingRecordZoneChange], engine: CKSyncEngine) {
        engine.state.remove(pendingRecordZoneChanges: pending)
        outgoing = [:]
        for url in tempFiles {
            do { try FileManager.default.removeItem(at: url) } catch {
                Self.log.error("Could not remove temporary upload file: \(error.localizedDescription, privacy: .public)")
            }
        }
        tempFiles = []
    }
}
