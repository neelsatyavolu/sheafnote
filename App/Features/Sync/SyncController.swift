import Foundation
import Observation
import SheafnoteCore

/// Owns the `SyncCoordinator`, mirrors its status into `AppServices.syncStatus`, and decides when a cycle runs:
/// on launch and foreground (background task), 1 s after the last local change, on a server push, and on demand.
@MainActor @Observable
final class SyncController {
    /// The live controller, for views that cannot receive it any other way (the library's status indicator).
    private(set) static weak var shared: SyncController?

    let services: AppServices
    let coordinator: SyncCoordinator
    private(set) var status: SyncStatus
    private(set) var isEnabled: Bool
    private(set) var awaitingAccountDecision: Bool
    private(set) var lastSyncDate: Date?
    /// Set when the saved sync settings could not be read and sync was switched off until the user turns it on again.
    private(set) var settingsProblem: String?

    @ObservationIgnored private var debounce: Task<Void, Never>?
    @ObservationIgnored private var changeObserver: (any NSObjectProtocol)?
    static let debounceDelay: Duration = .seconds(1)

    init(services: AppServices, transport: any CloudTransport, persistence: any SyncPersistence,
         ink: any InkMerging = PageInkMerger()) {
        self.services = services
        let coordinator = SyncCoordinator(context: services.context, transport: transport, ink: ink, persistence: persistence)
        self.coordinator = coordinator
        status = coordinator.status
        isEnabled = coordinator.isEnabled
        awaitingAccountDecision = coordinator.awaitingAccountDecision
        lastSyncDate = coordinator.lastSyncDate
        settingsProblem = coordinator.settingsProblem
        coordinator.onStatusChange = { [weak self] _, _ in self?.refresh() }
        refresh()
    }

    /// Hooks purges and model changes up to the coordinator. Call once.
    func startObserving() {
        Self.shared = self
        services.library.onPurge = { [weak self] records in
            self?.coordinator.recordPurged(records)
            self?.scheduleSync()
        }
        changeObserver = NotificationCenter.default.addObserver(forName: .sheafnoteModelDidChange, object: nil,
                                                                queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleSync() }
        }
    }

    func syncNow() async { await coordinator.syncNow() }

    func setEnabled(_ enabled: Bool) async { await coordinator.setEnabled(enabled) }

    func resolveAccountSwitch(upload: Bool) async { await coordinator.resolveAccountSwitch(upload: upload) }

    /// Debounced: runs a cycle one second after the last change.
    func scheduleSync() {
        guard coordinator.isEnabled else { return }
        debounce?.cancel()
        debounce = Task { [weak self] in
            do { try await Task.sleep(for: Self.debounceDelay) } catch { return }
            await self?.coordinator.syncNow()
        }
    }

    private func refresh() {
        status = coordinator.status
        isEnabled = coordinator.isEnabled
        awaitingAccountDecision = coordinator.awaitingAccountDecision
        lastSyncDate = coordinator.lastSyncDate
        settingsProblem = coordinator.settingsProblem
        let model = services.syncStatus
        model.state = Self.modelState(for: coordinator.status)
        model.isSyncEnabled = coordinator.isEnabled
        model.lastSyncDate = coordinator.lastSyncDate
    }

    static func modelState(for status: SyncStatus) -> SyncStatusModel.State {
        switch status {
        case .idle, .localOnly: .idle
        case .syncing: .syncing
        case .offline: .offline
        case .signedOut: .signedOut
        case .quotaExceeded: .quotaExceeded
        case .error(let message): .error(message)
        }
    }
}
