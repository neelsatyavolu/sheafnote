import Foundation
import SwiftData

public enum SyncStatus: Equatable, Sendable {
    case idle, syncing, offline, signedOut, quotaExceeded
    /// Sync is switched off in Settings (local-only mode).
    case localOnly
    case error(String)
}

/// What the last sync cycle did. Shown in diagnostics and asserted in tests.
public struct SyncReport: Equatable, Sendable {
    public var uploaded = 0
    public var created = 0
    public var updated = 0
    public var merged = 0
    public var keptBothVersions = 0
    public var removed = 0
    public var resurrected = 0
    public var ignored = 0
    public var conflictsResolved = 0

    public init() {}

    mutating func count(_ outcome: ApplyOutcome) {
        switch outcome {
        case .created: created += 1
        case .updated: updated += 1
        case .merged: merged += 1
        case .keptBothVersions: keptBothVersions += 1
        case .deleted: removed += 1
        case .resurrected: resurrected += 1
        case .ignored: ignored += 1
        }
    }
}

/// Runs sync cycles between the local SwiftData store and a `CloudTransport`:
/// fetch and apply server changes, then push local ones, resolving conflicts on the way.
///
/// Rules this type enforces:
/// - local data is never deleted because of an account event (sign-out, switch) or a failed sync;
/// - a record deleted on the server only removes a local row that is already in Recently Deleted;
/// - purged rows are deleted in CloudKit only after the 30-day window, through a persisted queue;
/// - turning sync off stops the engine and touches nothing else.
@MainActor
public final class SyncCoordinator {
    let context: ModelContext
    let transport: any CloudTransport
    let ink: any InkMerging
    let persistence: any SyncPersistence
    let clock: @Sendable () -> Date

    var state: SyncPersistedState
    var isRunning = false
    var rerunRequested = false
    var zoneRecoveries = 0

    public internal(set) var status: SyncStatus = .idle { didSet { notifyStatus() } }
    public internal(set) var lastReport = SyncReport()
    /// Called whenever the status or the last successful sync date changes.
    public var onStatusChange: (@MainActor (SyncStatus, Date?) -> Void)?

    public init(context: ModelContext, transport: any CloudTransport, ink: any InkMerging,
                persistence: any SyncPersistence, clock: @escaping @Sendable () -> Date = { Date() }) {
        self.context = context
        self.transport = transport
        self.ink = ink
        self.persistence = persistence
        self.clock = clock
        do {
            state = try persistence.load()
        } catch {
            state = SyncPersistedState()
            status = .error("Sync settings could not be read, so Sheafnote started with the defaults. \(error.localizedDescription)")
        }
        transport.onAccountEvent = { [weak self] event in
            guard let self else { return }
            Task { await self.handle(event) }
        }
    }

    public var isEnabled: Bool { state.isEnabled }
    public var lastSyncDate: Date? { state.lastSyncDate }
    public var awaitingAccountDecision: Bool { state.awaitingAccountDecision }
    public var pendingDeletionCount: Int { state.pendingDeletions.count }

    /// Call once at launch.
    public func start() async {
        await syncNow()
    }

    /// Turns iCloud sync on or off. Off is local-only mode: the engine stops, nothing is deleted.
    public func setEnabled(_ enabled: Bool) async {
        guard enabled != state.isEnabled else { return }
        state.isEnabled = enabled
        if enabled { state.needsFullUpload = true }
        persist()
        if enabled {
            await syncNow()
        } else {
            transport.stop()
            status = .localOnly
        }
    }

    /// Queues CloudKit deletions for rows that were purged for good (wire to `LibraryStore.onPurge`).
    public func recordPurged(_ records: [PurgedRecord]) {
        state.pendingDeletions = PurgePolicy.queueDeletions(existing: state.pendingDeletions, purged: records)
        persist()
    }

    /// Runs a full cycle. Safe to call at any time; concurrent calls are coalesced into one more pass.
    public func syncNow() async {
        guard !isRunning else {
            rerunRequested = true
            return
        }
        isRunning = true
        defer { isRunning = false }
        repeat {
            rerunRequested = false
            await runCycle()
        } while rerunRequested
    }

    func runCycle() async {
        guard state.isEnabled else {
            status = .localOnly
            return
        }
        guard !state.awaitingAccountDecision else { return }
        status = .syncing
        var report = SyncReport()
        do {
            switch await transport.accountStatus() {
            case .noAccount, .restricted:
                status = .signedOut
                return
            case .available, .unknown:
                break
            }
            try await transport.start()
            if state.needsFullUpload {
                try RecordMapper.markAllDirty(in: context)
                state.needsFullUpload = false
                persist()
            }
            try await fetchAndApply(into: &report)
            try await push(into: &report)
            state.lastSyncDate = clock()
            persist()
            zoneRecoveries = 0
            lastReport = report
            status = .idle
        } catch let failure as SyncFailure {
            lastReport = report
            await handle(failure)
        } catch {
            lastReport = report
            status = .error(error.localizedDescription)
        }
    }

    func fetchAndApply(into report: inout SyncReport) async throws {
        let changes = try await transport.fetchChanges()
        if changes.zoneDeleted { throw SyncFailure.zoneNotFound }
        let queued = Set(state.pendingDeletions)
        for record in changes.records where !queued.contains(record.key) {
            report.count(try RecordMapper.applyServer(record, in: context, ink: ink, now: clock(), save: false))
        }
        for key in changes.deletions {
            report.count(try RecordMapper.applyServerDeletion(key, in: context, save: false))
        }
        try context.save()
    }

    func handle(_ failure: SyncFailure) async {
        switch failure {
        case .offline: status = .offline
        case .quotaExceeded: status = .quotaExceeded
        case .notAuthenticated: status = .signedOut
        case .zoneNotFound: await recoverFromMissingZone()
        case .rateLimited, .other: status = .error(failure.userMessage)
        }
    }

    /// The zone is gone (user cleared iCloud data, or it was never created): make a new one and upload everything.
    func recoverFromMissingZone() async {
        zoneRecoveries += 1
        guard zoneRecoveries <= 2 else {
            status = .error(SyncFailure.zoneNotFound.userMessage)
            return
        }
        do {
            try await transport.start()
            await transport.resetState()
            try RecordMapper.markAllDirty(in: context)
            rerunRequested = true
        } catch let failure as SyncFailure {
            await handle(failure)
        } catch {
            status = .error(error.localizedDescription)
        }
    }

    func persist() {
        do {
            try persistence.save(state)
        } catch {
            status = .error("Sync settings could not be saved. \(error.localizedDescription)")
        }
    }

    private func notifyStatus() { onStatusChange?(status, state.lastSyncDate) }
}
