import SheafnoteCore
import SwiftUI

/// "Lock" / "Unlock" in the notebook context menu. Locking needs no check; removing a lock asks the device first.
enum NotebookLockAction {
    static let action = NotebookContextAction(
        id: "docTypes.lock", title: LocalizedStringResource("Lock or Unlock", table: "DocTypes"),
        symbolName: "lock", order: 80, isDestructive: false
    ) { notebooks, context in
        try await toggle(notebooks, context: context)
    }

    @MainActor
    static func toggle(_ notebooks: [Notebook], context: LibraryActionContext,
                       controller: AppLockController = .shared) async throws {
        guard !notebooks.isEmpty else { return }
        let locking = notebooks.contains { !$0.isLocked }
        if !locking {
            for notebook in notebooks where controller.requiresUnlock(notebook) {
                guard await controller.unlockNotebook(notebook.id) else { return }
            }
        }
        try setLocked(locking, notebooks, services: context.services)
    }

    @MainActor
    static func setLocked(_ locked: Bool, _ notebooks: [Notebook], services: AppServices) throws {
        for notebook in notebooks where notebook.isLocked != locked {
            notebook.isLocked = locked
            markDirty(notebook, fields: ["isLocked"])
        }
        do {
            try services.context.save()
        } catch {
            throw DocTypesError.saveFailed(error.localizedDescription)
        }
    }
}
