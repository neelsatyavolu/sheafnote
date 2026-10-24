import Foundation
import PencilKit
import SwiftData
import Testing
import SheafnoteCore
@testable import Sheafnote

@MainActor
@Suite struct SyncControllerTests {
    private func controller(enabled: Bool = true, cloud: InMemoryCloud = InMemoryCloud()) throws
        -> (SyncController, AppServices, InMemoryTransport) {
        let services = try AppServices.inMemory()
        let transport = InMemoryTransport(cloud: cloud)
        var state = SyncPersistedState()
        state.isEnabled = enabled
        let controller = SyncController(services: services, transport: transport, persistence: InMemorySyncPersistence(state: state))
        return (controller, services, transport)
    }

    @Test func statusModelReflectsEachCoordinatorStatus() {
        #expect(SyncController.modelState(for: .idle) == .idle)
        #expect(SyncController.modelState(for: .localOnly) == .idle)
        #expect(SyncController.modelState(for: .syncing) == .syncing)
        #expect(SyncController.modelState(for: .offline) == .offline)
        #expect(SyncController.modelState(for: .signedOut) == .signedOut)
        #expect(SyncController.modelState(for: .quotaExceeded) == .quotaExceeded)
        #expect(SyncController.modelState(for: .error("boom")) == .error("boom"))
    }

    @Test func syncUpdatesTheSharedStatusModel() async throws {
        let (c, services, transport) = try controller()
        try services.library.createFolder(name: "F", in: nil)
        await c.syncNow()
        #expect(services.syncStatus.state == .idle && services.syncStatus.lastSyncDate != nil && services.syncStatus.isSyncEnabled)
        transport.isOnline = false
        await c.syncNow()
        #expect(services.syncStatus.state == .offline)
        transport.account = .noAccount
        transport.isOnline = true
        await c.syncNow()
        #expect(services.syncStatus.state == .signedOut)
    }

    @Test func localOnlyToggleIsMirrored() async throws {
        let (c, services, transport) = try controller()
        await c.setEnabled(false)
        #expect(!c.isEnabled && !services.syncStatus.isSyncEnabled && c.status == .localOnly)
        try services.library.createFolder(name: "Private", in: nil)
        await c.syncNow()
        #expect(transport.savesSent.isEmpty)
        await c.setEnabled(true)
        #expect(c.isEnabled && services.syncStatus.isSyncEnabled && !transport.savesSent.isEmpty)
    }

    @Test func localChangesTriggerADebouncedSync() async throws {
        let (c, services, transport) = try controller()
        c.startObserving()
        try services.library.createFolder(name: "Debounced", in: nil)
        #expect(transport.savesSent.isEmpty)
        try await Task.sleep(for: .milliseconds(1_600))
        #expect(!transport.savesSent.isEmpty)
    }

    @Test func purgedRowsAreQueuedForCloudKitDeletion() async throws {
        let (c, services, _) = try controller()
        c.startObserving()
        let nb = try services.library.createNotebook(title: "Old", kind: .paged, cover: .default, template: .blank, paperSize: .a4,
                                                     orientation: .portrait, paperColor: .white, in: nil)
        try services.library.softDelete([.notebook(nb.id)], now: .now.addingTimeInterval(-40 * 86_400))
        _ = try services.library.purgeExpired()
        #expect(c.coordinator.pendingDeletionCount > 0)
    }

    @Test func accountSwitchQuestionIsMirroredAndAnswerable() async throws {
        let (c, _, transport) = try controller()
        await c.syncNow()
        transport.simulate(.switched)
        try await Task.sleep(for: .milliseconds(100))
        #expect(c.awaitingAccountDecision)
        await c.resolveAccountSwitch(upload: false)
        #expect(!c.awaitingAccountDecision && !c.isEnabled)
    }

    @Test func statusPresentationHasTextForEveryStatus() {
        let all: [SyncStatus] = [.idle, .syncing, .offline, .signedOut, .quotaExceeded, .localOnly, .error("Detail")]
        for status in all {
            let p = SyncStatusPresentation(status: status)
            #expect(!p.title.isEmpty && !p.detail.isEmpty && !p.symbolName.isEmpty)
        }
        #expect(SyncStatusPresentation(status: .error("Detail")).detail == "Detail")
        #expect(SyncStatusPresentation(status: .signedOut).needsAttention)
        #expect(!SyncStatusPresentation(status: .idle).needsAttention)
    }

    @Test func syncFeatureRegistersItsSettingsSection() throws {
        let host = FeatureHost(services: try AppServices.inMemory())
        SyncFeature.register(into: host)
        let section = try #require(host.settings.sections.first { $0.id == "sync" })
        #expect(section.order == 20 && section.symbolName == "icloud")
        #expect(!SyncFeature.usesRealCloud)
    }
}
