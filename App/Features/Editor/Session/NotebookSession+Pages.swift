import Foundation
import SheafnoteCore

/// Page operations. Every one is undoable, and none removes data for good: deleting a page is a soft delete
/// (with a recovery snapshot taken by `PageStore`) that undo reverses.
extension NotebookSession {
    // MARK: Add

    @discardableResult
    func addPage(_ position: PagePosition, template: TemplateSpec?, paperColor: PaperColor? = nil) -> UUID? {
        do {
            let page = try services.pages.addPage(to: notebook.id, at: position, template: template)
            if let paperColor {
                page.paperColorOverride = paperColor.rawValue
                markDirty(page, fields: ["paperColorOverride"])
                try services.context.save()
            }
            registerPageUndo("Add Page") { $0.removePages([page.id]) }
            reloadPages()
            goToPage(id: page.id, animated: true)
            return page.id
        } catch {
            report(error)
            return nil
        }
    }

    // MARK: Duplicate

    func duplicatePages(_ ids: [UUID]) {
        var created: [UUID] = []
        do {
            for id in ids { created.append(try services.pages.duplicate(pageID: id).id) }
        } catch {
            report(error)
        }
        guard !created.isEmpty else { return }
        registerPageUndo("Duplicate Page") { $0.removePages(created) }
        reloadPages()
        if let last = created.last { goToPage(id: last, animated: true) }
    }

    // MARK: Delete and restore

    /// A notebook always keeps at least one page.
    func deletePages(_ ids: [UUID]) {
        let remaining = pageIDs.filter { !ids.contains($0) }
        guard !remaining.isEmpty else {
            showToast(LocalizedStringResource("A notebook needs at least one page.", table: "Editor"))
            return
        }
        removePages(ids)
        if let current = currentPageID, ids.contains(current), let first = remaining.first { goToPage(id: first, animated: false) }
    }

    fileprivate func removePages(_ ids: [UUID]) {
        let present = ids.filter { pageIDs.contains($0) }
        guard !present.isEmpty else { return }
        do {
            try services.pages.softDelete(pageIDs: present)
        } catch {
            report(error)
            return
        }
        registerPageUndo("Delete Page") { $0.restorePages(present) }
        reloadPages()
    }

    fileprivate func restorePages(_ ids: [UUID]) {
        do {
            for id in ids {
                guard let page = services.pages.page(id: id) else { continue }
                page.deletedAt = nil
                markDirty(page, fields: ["deletedAt"])
            }
            try services.context.save()
        } catch {
            report(error)
            return
        }
        registerPageUndo("Restore Page") { $0.removePages(ids) }
        reloadPages()
    }

    // MARK: Template

    func changeTemplate(pageIDs ids: [UUID], template: TemplateSpec, paperColor: PaperColor) {
        let before: [(UUID, Data?, String?)] = ids.compactMap { id in
            services.pages.page(id: id).map { ($0.id, $0.templateOverride, $0.paperColorOverride) }
        }
        do {
            for id in ids { try setPaper(id, template: JSONCoding.encode(template), color: paperColor.rawValue) }
        } catch {
            report(error)
            return
        }
        registerPageUndo("Change Template") { s in s.restorePaper(before) }
    }

    fileprivate func restorePaper(_ values: [(UUID, Data?, String?)]) {
        let current: [(UUID, Data?, String?)] = values.compactMap { id, _, _ in
            services.pages.page(id: id).map { ($0.id, $0.templateOverride, $0.paperColorOverride) }
        }
        do {
            for (id, template, color) in values { try setPaper(id, template: template, color: color) }
        } catch {
            report(error)
            return
        }
        registerPageUndo("Change Template") { s in s.restorePaper(current) }
    }

    private func setPaper(_ id: UUID, template: Data?, color: String?) throws {
        guard let page = services.pages.page(id: id) else { return }
        page.templateOverride = template
        page.paperColorOverride = color
        markDirty(page, fields: ["templateOverride", "paperColorOverride"])
        try services.context.save()
        pageSessions[id]?.refreshSnapshot()
        layoutRevision += 1
    }

    // MARK: Reorder

    /// Moves `id` so it sits directly before or after `target`, using fractional sort keys (no other page is rewritten).
    func movePage(_ id: UUID, relativeTo target: UUID, after: Bool) {
        guard id != target, let from = pageIDs.firstIndex(of: id), pageIDs.contains(target) else { return }
        var order = pageIDs
        order.remove(at: from)
        guard let targetIndex = order.firstIndex(of: target) else { return }
        let insertAt = after ? targetIndex + 1 : targetIndex
        let previous = insertAt > 0 ? order[insertAt - 1] : nil
        let next = insertAt < order.count ? order[insertAt] : nil
        movePage(id, between: previous, and: next)
    }

    fileprivate func movePage(_ id: UUID, between previous: UUID?, and next: UUID?) {
        guard let from = pageIDs.firstIndex(of: id) else { return }
        let oldPrevious = from > 0 ? pageIDs[from - 1] : nil
        let oldNext = from + 1 < pageIDs.count ? pageIDs[from + 1] : nil
        do {
            try services.pages.move(pageID: id, between: previous, and: next)
        } catch {
            report(error)
            return
        }
        registerPageUndo("Move Page") { $0.movePage(id, between: oldPrevious, and: oldNext) }
        reloadPages()
    }

    // MARK: Undo plumbing

    private func registerPageUndo(_ name: String, _ action: @escaping @MainActor (NotebookSession) -> Void) {
        undoManager.registerMain(target: self, action)
        if !undoManager.isUndoing, !undoManager.isRedoing {
            undoManager.setActionName(String(localized: String.LocalizationValue(name), table: "Editor"))
        }
    }
}
