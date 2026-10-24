import CloudKit
import Foundation
import SheafnoteCore

/// Events collected from the engine between explicit fetch/send calls.
struct EventBuffer {
    var records: [SyncRecord] = []
    var deletions: [RecordKey] = []
    var zoneDeleted = false
    var sent: [CKSyncEngine.Event.SentRecordZoneChanges] = []
    var error: (any Error)?

    mutating func clearFetched() {
        records = []
        deletions = []
        zoneDeleted = false
    }
}

extension CKSyncEngineTransport: CKSyncEngineDelegate {
    nonisolated func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        await receive(event)
    }

    nonisolated func nextRecordZoneChangeBatch(_ context: CKSyncEngine.SendChangesContext,
                                               syncEngine: CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let pending = await currentPendingChanges(for: context, in: syncEngine)
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: pending) { id in
            await self.recordToSend(for: id)
        }
    }

    /// Pending changes the engine remembers from an earlier run, and that this run has no snapshot for, are dropped:
    /// the local store still marks those rows dirty and the next cycle re-adds them with fresh data.
    private func currentPendingChanges(for context: CKSyncEngine.SendChangesContext,
                                       in engine: CKSyncEngine) -> [CKSyncEngine.PendingRecordZoneChange] {
        let inScope = engine.state.pendingRecordZoneChanges.filter { context.options.scope.contains($0) }
        let stale = inScope.filter { outgoing[Self.recordID(of: $0)] == nil }
        if !stale.isEmpty { engine.state.remove(pendingRecordZoneChanges: stale) }
        return inScope.filter { outgoing[Self.recordID(of: $0)] != nil }
    }

    private static func recordID(of change: CKSyncEngine.PendingRecordZoneChange) -> CKRecord.ID {
        switch change {
        case .saveRecord(let id), .deleteRecord(let id): id
        @unknown default: CKRecord.ID(recordName: "unknown", zoneID: CKRecordBridge.zoneID)
        }
    }

    func recordToSend(for id: CKRecord.ID) -> CKRecord? {
        guard case .save(let record)? = outgoing[id] else { return nil }
        do {
            let built = try CKRecordBridge.ckRecord(for: record, assetDirectory: assetDirectory)
            tempFiles.append(contentsOf: built.tempFiles)
            return built.record
        } catch {
            buffer.error = error
            return nil
        }
    }

    func receive(_ event: CKSyncEngine.Event) {
        switch event {
        case .stateUpdate(let update):
            persisted.serialization = update.stateSerialization
            persistState()
        case .accountChange(let change):
            onAccountEvent?(Self.accountEvent(for: change.changeType))
        case .fetchedDatabaseChanges(let changes):
            if changes.deletions.contains(where: { $0.zoneID == CKRecordBridge.zoneID }) {
                buffer.zoneDeleted = true
                persisted.zoneCreated = false
            }
        case .fetchedRecordZoneChanges(let changes):
            collect(changes)
            if explicitOperations == 0 { onRemoteChange?() }
        case .sentDatabaseChanges(let sent):
            if sent.savedZones.contains(where: { $0.zoneID == CKRecordBridge.zoneID }) {
                persisted.zoneCreated = true
                persistState()
            }
            if let failure = sent.failedZoneSaves.first { buffer.error = failure.error }
        case .sentRecordZoneChanges(let sent):
            buffer.sent.append(sent)
        default:
            break
        }
    }

    private func collect(_ changes: CKSyncEngine.Event.FetchedRecordZoneChanges) {
        for modification in changes.modifications {
            do {
                if let record = try CKRecordBridge.syncRecord(from: modification.record) { buffer.records.append(record) }
            } catch {
                buffer.error = error
            }
        }
        for deletion in changes.deletions {
            guard let id = UUID(uuidString: deletion.recordID.recordName) else { continue }
            buffer.deletions.append(RecordKey(recordType: deletion.recordType, id: id))
        }
    }

    private static func accountEvent(for change: CKSyncEngine.Event.AccountChange.ChangeType) -> AccountEvent {
        switch change {
        case .signIn: .signedIn
        case .signOut: .signedOut
        case .switchAccounts: .switched
        @unknown default: .switched
        }
    }

    private func persistState() {
        do { try stateStore.save(persisted) } catch {
            Self.log.error("Could not save sync state: \(error.localizedDescription, privacy: .public)")
            buffer.error = error
        }
    }

    /// One outcome per requested change, from the engine's `sentRecordZoneChanges` events.
    func outcomes(for changes: [OutgoingChange]) -> [SendOutcome] {
        var byID: [CKRecord.ID: SendOutcome] = [:]
        for sent in buffer.sent {
            for saved in sent.savedRecords {
                guard case .save(let record)? = outgoing[saved.recordID] else { continue }
                do {
                    guard let savedRecord = try CKRecordBridge.syncRecord(from: saved) else { continue }
                    byID[saved.recordID] = .saved(sent: record, saved: savedRecord)
                } catch {
                    byID[saved.recordID] = .failed(record.key, CKErrorMapping.failure(from: error))
                }
            }
            for failed in sent.failedRecordSaves {
                guard case .save(let record)? = outgoing[failed.record.recordID] else { continue }
                byID[failed.record.recordID] = CKErrorMapping.outcome(forFailedSave: failed.record, error: failed.error, sent: record)
            }
            for id in sent.deletedRecordIDs {
                if case .delete(let key)? = outgoing[id] { byID[id] = .deleted(key) }
            }
            for (id, error) in sent.failedRecordDeletes {
                guard case .delete(let key)? = outgoing[id] else { continue }
                // Already gone on the server counts as deleted.
                byID[id] = error.code == .unknownItem ? .deleted(key) : .failed(key, CKErrorMapping.failure(from: error))
            }
        }
        buffer.sent = []
        return changes.map { change in
            let id = CKRecordBridge.recordID(for: Self.key(of: change))
            return byID[id] ?? .failed(Self.key(of: change), .other("iCloud has not confirmed this change yet."))
        }
    }

    private static func key(of change: OutgoingChange) -> RecordKey {
        switch change {
        case .save(let record): record.key
        case .delete(let key): key
        }
    }
}
