import PencilKit
import SheafnoteCore

/// Keeps an open page and the store in step when iCloud sync changes the page's ink behind the editor's back.
extension PageSession {
    /// Records that the store now holds exactly the ink just written, so later changes can be told apart from ours.
    func noteSaved(hash: String, strokeIDs: [StrokeID]) {
        storedInkHash = hash
        storedStrokeIDs = strokeIDs.map(\.rawValue)
    }

    /// Compares the store with what this editor last loaded or saved. When sync wrote newer ink:
    /// - nothing unsaved here: show the new ink;
    /// - unsaved strokes here: merge both (the unsaved version is snapshotted into Recovered first) and save.
    /// Returns true when the store was written, so the caller must not write the older in-memory ink over it.
    @discardableResult
    func reconcileWithStore() -> Bool {
        guard loadProblem == nil else { return reloadUnreadablePage() }
        do {
            let unsaved = saver.hasUnsavedChanges
                ? InkState(data: drawing.dataRepresentation(), strokeIDs: strokeIDs.map(\.rawValue)) : nil
            let outcome = try services.pages.reconcileInk(pageID: pageID, knownHash: storedInkHash,
                                                          baseStrokeIDs: storedStrokeIDs, unsaved: unsaved,
                                                          ink: PageInkMerger())
            return apply(outcome)
        } catch {
            notebook.report(error)
            return false
        }
    }

    private func apply(_ outcome: InkReconcileOutcome) -> Bool {
        switch outcome {
        case .unchanged:
            return false
        case .adopted(let state):
            showStoredInk(state)
            return false
        case .merged(let state):
            showStoredInk(state)
            saver.markSaved()
            notebook.showToast(LocalizedStringResource("Merged your latest writing with changes from iCloud.", table: "Editor"))
            return true
        case .keptLocal:
            adoptStoredIdentity()
            saver.markSaved()
            notebook.showToast(LocalizedStringResource("Your writing was kept. The iCloud version of this page is in Recovered Pages.", table: "Editor"))
            return true
        }
    }

    /// Replaces the live drawing with ink that came from the store. Undo steps recorded against the old drawing would
    /// bring back a state without the remote strokes, so the notebook's undo history starts over.
    private func showStoredInk(_ state: InkState) {
        do {
            let new = try state.data.flatMap { $0.isEmpty ? nil : $0 }.map { try PKDrawing(data: $0) } ?? PKDrawing()
            replaceDrawingFromStore(new)
        } catch {
            markUnreadable()
        }
        adoptStoredIdentity()
    }

    private func adoptStoredIdentity() {
        guard let stored = services.pages.page(id: pageID) else { return }
        storedInkHash = stored.inkHash
        storedStrokeIDs = stored.strokeIDs
    }

    /// A page that was read-only because its ink had not arrived becomes editable once sync delivered it.
    private func reloadUnreadablePage() -> Bool {
        guard let stored = services.pages.page(id: pageID) else { return false }
        let result = Self.load(stored)
        guard result.problem == nil else { return false }
        clearLoadProblem()
        replaceDrawingFromStore(result.drawing)
        adoptStoredIdentity()
        return false
    }
}
