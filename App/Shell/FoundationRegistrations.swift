import OSLog
import SheafnoteCore
import SwiftUI

/// Foundation's own entries in the extension-point registries.
@MainActor
enum FoundationRegistrations {
    private static let log = Logger(subsystem: "co.xanom.sheafnote", category: "maintenance")

    static func register(into host: FeatureHost) {
        registerLibraryItems(into: host)
        host.settings.register(GeneralSettings.section)
        host.settings.register(AboutSettings.section)
        host.library.registerBackgroundTask(id: LibraryMenuRegistry.retentionTaskID) { services in
            runRetention(services)
        }
    }

    private static func registerLibraryItems(into host: FeatureHost) {
        host.library.registerNewItem(LibraryNewItem(
            id: "notebook", title: "Notebook", symbolName: "book.closed", order: 0) { ctx in
                ctx.present(AnyView(NewNotebookSheet(services: ctx.services, folderID: ctx.currentFolderID, onCreated: ctx.open)))
            })
        host.library.registerNewItem(LibraryNewItem(
            id: "folder", title: "Folder", symbolName: "folder.badge.plus", order: 10) { ctx in
                ctx.present(AnyView(NewFolderSheet(services: ctx.services, parentID: ctx.currentFolderID)))
            })
    }

    static func retentionShouldWait(for status: SyncStatus) -> Bool {
        switch status {
        case .offline, .error: true
        case .idle, .syncing, .signedOut, .quotaExceeded, .localOnly: false
        }
    }

    /// 30-day purge of Recently Deleted items and expired recovery snapshots.
    static func runRetention(_ services: AppServices) {
        // A failed or offline sync means this device's view may be stale: purging now could queue deletions that
        // override a restore made on another device. Try again next time.
        if let sync = SyncController.shared, sync.isEnabled, retentionShouldWait(for: sync.status) {
            log.info("Retention postponed until sync has caught up")
            return
        }
        do {
            let removed = try services.library.purgeExpired()
            let revisions = try services.revisions.purgeExpired()
            if removed + revisions > 0 { log.info("Retention removed \(removed) library items, \(revisions) snapshots") }
        } catch {
            log.error("Retention failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
