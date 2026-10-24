import Foundation

extension SyncCoordinator {
    static let maxBatchRecords = 50
    static let maxBatchBytes = 20_000_000
    static let maxPushRounds = 6

    /// Sends dirty rows and queued deletions until nothing is left. A conflict leaves the merged row dirty,
    /// so the next round sends it against the fresh server version.
    func push(into report: inout SyncReport) async throws {
        for _ in 0..<Self.maxPushRounds {
            let batches = try nextBatches()
            if batches.isEmpty { return }
            var failure: SyncFailure?
            for batch in batches {
                let outcomes = try await transport.send(batch)
                let batchFailure = try process(outcomes, into: &report)
                failure = failure ?? batchFailure
            }
            try context.save()
            persist()
            if let failure { throw failure }
        }
        if try hasPendingWork() {
            throw SyncFailure.other("Sync is still catching up. Sheafnote will try again shortly.")
        }
    }

    func hasPendingWork() throws -> Bool {
        let dirty = try RecordMapper.dirtyKeys(in: context)
        return !dirty.isEmpty || !state.pendingDeletions.isEmpty
    }

    /// Dirty rows and queued deletions, split into batches bounded by record count and payload size.
    func nextBatches() throws -> [[OutgoingChange]] {
        var changes: [OutgoingChange] = []
        for key in try RecordMapper.dirtyKeys(in: context) {
            if let record = try RecordMapper.encode(key, in: context) { changes.append(.save(record)) }
        }
        for key in state.pendingDeletions {
            if try RecordMapper.exists(key, in: context) {
                state.pendingDeletions.removeAll { $0 == key }   // the row exists again: it wins
            } else {
                changes.append(.delete(key))
            }
        }
        return Self.batches(changes)
    }

    static func batches(_ changes: [OutgoingChange]) -> [[OutgoingChange]] {
        var result: [[OutgoingChange]] = []
        var current: [OutgoingChange] = []
        var bytes = 0
        for change in changes {
            let size = payloadSize(of: change)
            if !current.isEmpty && (current.count >= maxBatchRecords || bytes + size > maxBatchBytes) {
                result.append(current)
                current = []
                bytes = 0
            }
            current.append(change)
            bytes += size
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    private static func payloadSize(of change: OutgoingChange) -> Int {
        guard case .save(let record) = change else { return 0 }
        return record.fields.values.reduce(0) { total, value in
            if case .bytes(let data) = value { total + data.count } else { total }
        }
    }

    /// Applies per-record results. Returns the first failure that should surface after the batch.
    func process(_ outcomes: [SendOutcome], into report: inout SyncReport) throws -> SyncFailure? {
        var failure: SyncFailure?
        for outcome in outcomes {
            switch outcome {
            case .saved(let sent, let saved):
                try RecordMapper.confirmSent(sent: sent, saved: saved, in: context)
                report.uploaded += 1
            case .deleted(let key):
                state.pendingDeletions.removeAll { $0 == key }
                report.removed += 1
            case .conflict(_, let server):
                report.count(try RecordMapper.applyServer(server, in: context, ink: ink, now: clock(), save: false))
                report.conflictsResolved += 1
            case .missingOnServer(let sent):
                try RecordMapper.forgetServerVersion(sent.key, in: context)
            case .failed(_, let reason):
                failure = failure ?? reason
            }
        }
        return failure
    }
}
