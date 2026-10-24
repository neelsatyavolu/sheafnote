import Foundation
import SwiftData
import SheafnoteCore

/// `PageElementStore` for one page: persists through `PageStore`, keeps value copies for the live element layer
/// and registers undo on the notebook's manager. Deleting is always a soft delete, so undo can bring elements back.
@MainActor
final class PageElements: PageElementStore {
    private unowned let page: PageSession

    init(page: PageSession) { self.page = page }

    var all: [ElementValue] { page.elementValues }

    @discardableResult
    func add(_ element: ElementValue, undoName: LocalizedStringResource) throws -> ElementValue {
        var value = element
        value.pageID = page.pageID
        let stored = try page.services.pages.insertElement(value)
        page.reloadElements()
        registerUndo(name: undoName) { store in store.run { try store.remove(ids: [stored.id], undoName: undoName) } }
        return stored
    }

    func update(id: UUID, undoName: LocalizedStringResource, _ mutate: (inout ElementValue) -> Void) throws {
        guard let before = all.first(where: { $0.id == id }) else { return }
        try page.services.pages.updateElement(id: id, mutate)
        page.reloadElements()
        registerUndo(name: undoName) { store in
            store.run { try store.page.services.pages.updateElement(id: id) { $0 = before } }
            store.page.reloadElements()
        }
    }

    func remove(ids: Set<UUID>, undoName: LocalizedStringResource) throws {
        let existing = ids.intersection(Set(all.map(\.id)))
        guard !existing.isEmpty else { return }
        try page.services.pages.softDeleteElements(ids: existing)
        page.reloadElements()
        registerUndo(name: undoName) { store in store.run { try store.restore(ids: existing) } }
    }

    /// Reverses a soft delete.
    func restore(ids: Set<UUID>) throws {
        let context = page.services.context
        let rows = try context.fetch(FetchDescriptor<PageElement>(predicate: #Predicate { ids.contains($0.id) }))
        for row in rows {
            row.deletedAt = nil
            markDirty(row, fields: ["deletedAt"])
        }
        try context.save()
        page.reloadElements()
        let removed = ids
        registerUndo(name: "Delete") { store in store.run { try store.remove(ids: removed, undoName: "Delete") } }
    }

    /// Runs an undo/redo step; a failure is shown to the user instead of being dropped.
    private func run(_ work: () throws -> Void) {
        do { try work() } catch { page.notebook.report(error) }
    }

    private func registerUndo(name: LocalizedStringResource, _ body: @escaping @MainActor (PageElements) -> Void) {
        let pageID = page.pageID
        let session = page.notebook
        session.undoManager.registerMain(target: session) { s in
            guard let store = s.pageSession(for: pageID)?.elementStore else { return }
            body(store)
        }
        if !session.undoManager.isUndoing, !session.undoManager.isRedoing {
            session.undoManager.setActionName(String(localized: name))
        }
    }
}
