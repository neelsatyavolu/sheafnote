import Foundation
import OSLog
import SheafnoteCore
import UIKit

/// iCloud sync: a `CKSyncEngine` layer over the local SwiftData store. See README, "Sync and CloudKit".
enum SyncFeature: FeatureModule {
    static let id = "sync"
    private static let log = Logger(subsystem: "co.xanom.sheafnote", category: "sync")

    static func register(into host: FeatureHost) {
        let controller = makeController(services: host.services)
        controller.startObserving()
        host.settings.register(SyncSettings.section(controller: controller))
        host.library.registerBackgroundTask(id: "sync.foreground") { _ in await controller.syncNow() }
        AppDelegate.remoteNotificationHandler = { _ in
            await controller.syncNow()
            return .newData
        }
    }

    /// UI tests and unit tests never touch CloudKit: they get an in-memory cloud and sync switched off.
    static var usesRealCloud: Bool {
        let env = ProcessInfo.processInfo.environment
        let isUnitTest = env["XCTestConfigurationFilePath"] != nil || env["XCTestBundlePath"] != nil
        return !UITestSeed.isActive && !isUnitTest
    }

    /// `CKContainer` traps in a process without the iCloud entitlement, and the unsigned simulator builds used for
    /// development and CI have none. There, sync reports "not signed in" instead of crashing. Set
    /// `SHEAFNOTE_CLOUDKIT_IN_SIMULATOR=1` for a signed simulator build with an iCloud account.
    static var cloudKitAvailable: Bool {
        #if targetEnvironment(simulator)
        return ProcessInfo.processInfo.environment["SHEAFNOTE_CLOUDKIT_IN_SIMULATOR"] == "1"
        #else
        return true
        #endif
    }

    private static func makeController(services: AppServices) -> SyncController {
        guard usesRealCloud else {
            var state = SyncPersistedState()
            state.isEnabled = false
            return SyncController(services: services, transport: InMemoryTransport(cloud: InMemoryCloud()),
                                  persistence: InMemorySyncPersistence(state: state))
        }
        guard cloudKitAvailable else {
            let transport = InMemoryTransport(cloud: InMemoryCloud())
            transport.account = .noAccount
            return SyncController(services: services, transport: transport, persistence: InMemorySyncPersistence())
        }
        do {
            let persistence = FileSyncPersistence(url: try FileSyncPersistence.defaultURL())
            let transport = CKSyncEngineTransport(stateStore: EngineStateStore(url: try EngineStateStore.defaultURL()))
            return SyncController(services: services, transport: transport, persistence: persistence)
        } catch {
            // No place to keep sync state: stay local-only rather than sync without a way to remember progress.
            log.error("Sync state folder unavailable: \(error.localizedDescription, privacy: .public)")
            var state = SyncPersistedState()
            state.isEnabled = false
            return SyncController(services: services, transport: InMemoryTransport(cloud: InMemoryCloud()),
                                  persistence: InMemorySyncPersistence(state: state))
        }
    }
}
