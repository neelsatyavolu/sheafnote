import Foundation
import PencilKit
import SheafnoteCore

/// Debounced autosave for one page: waits for 1 s without edits, encodes the drawing and its stroke ids off the main
/// thread, then writes through `PageStore.saveInk`. A failed write keeps the page marked unsaved and retries; the
/// failure is shown to the user. `flushNow` writes synchronously (page leaves the viewport, app backgrounds, editor closes).
@MainActor
final class InkSaveScheduler {
    static let debounce: Duration = .seconds(1)
    static let retryDelay: Duration = .seconds(5)

    weak var owner: PageSession?
    private(set) var hasUnsavedChanges = false
    private var task: Task<Void, Never>?
    private var savedVersion = -1
    private var lastNotebookTouch = Date.distantPast

    func markChanged() {
        hasUnsavedChanges = true
        schedule(after: Self.debounce)
    }

    private func schedule(after delay: Duration) {
        task?.cancel()
        task = Task { [weak self] in
            do { try await Task.sleep(for: delay) } catch { return }   // cancelled: a newer edit rescheduled
            await self?.saveInBackground()
        }
    }

    private func saveInBackground() async {
        guard let page = owner, hasUnsavedChanges, page.isEditable else { return }
        let version = page.drawingVersion
        let box = SendableDrawing(drawing: page.drawing)
        let encoded = await Task.detached(priority: .utility) {
            (box.drawing.dataRepresentation(), box.drawing.strokeIDs)
        }.value
        // A newer edit already rescheduled its own save; writing this older result would only be overwritten.
        guard version == page.drawingVersion else { return }
        write(data: encoded.0, ids: encoded.1, version: version, page: page)
    }

    func flushNow() {
        guard let page = owner, hasUnsavedChanges, page.isEditable else { return }
        task?.cancel()
        let drawing = page.drawing
        write(data: drawing.dataRepresentation(), ids: page.strokeIDs, version: page.drawingVersion, page: page)
    }

    private func write(data: Data, ids: [StrokeID], version: Int, page: PageSession) {
        do {
            try page.services.pages.saveInk(pageID: page.pageID, drawingData: data, strokeIDs: ids)
            savedVersion = version
            hasUnsavedChanges = page.drawingVersion != version
            page.notebook.clearSaveError()
            touchNotebook(page)
        } catch {
            hasUnsavedChanges = true
            page.notebook.reportSaveFailure(error)
            schedule(after: Self.retryDelay)
        }
    }

    /// Keeps "sort by modified" honest without re-sending the notebook record on every stroke.
    private func touchNotebook(_ page: PageSession) {
        let now = Date.now
        guard now.timeIntervalSince(lastNotebookTouch) > 60 else { return }
        lastNotebookTouch = now
        markDirty(page.notebook.notebook, fields: [], now: now)
    }
}
