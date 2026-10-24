import Foundation
import SwiftData

public enum InkReconcileOutcome: Equatable, Sendable {
    /// The stored ink is the version the editor already knows.
    case unchanged
    /// The stored ink changed under the editor (sync) and the editor had nothing unsaved: show this ink.
    case adopted(InkState)
    /// The editor had unsaved ink as well: both were merged, saved, and the editor must show the merged ink.
    case merged(InkState)
    /// The two versions could not be merged. The editor's ink was saved, the other version is kept as a conflict revision.
    case keptLocal
}

public extension PageStore {
    /// Brings an open editor and the store back together after sync changed a page's ink behind the editor's back.
    ///
    /// - Parameters:
    ///   - knownHash: `inkHash` of the stored ink the editor last loaded or saved.
    ///   - baseStrokeIDs: stroke ids of that same stored ink (the three-way merge base).
    ///   - unsaved: the editor's in-memory ink when it has changes not yet written, otherwise nil.
    /// The editor's unsaved ink is always snapshotted into the Recovered area first; nothing is dropped silently.
    func reconcileInk(pageID: UUID, knownHash: String, baseStrokeIDs: [String], unsaved: InkState?,
                      ink: any InkMerging, now: Date = .now) throws -> InkReconcileOutcome {
        guard let page = page(id: pageID) else { throw StoreError.notFound("the page") }
        guard page.inkHash != knownHash else { return .unchanged }
        let theirs = InkState(data: page.inkData, strokeIDs: page.strokeIDs)
        guard let ours = unsaved else { return .adopted(theirs) }
        context.insert(PageRevision(pageID: page.id, notebookID: page.notebookID, reason: .conflict, createdAt: now,
                                    inkData: ours.data, strokeIDs: ours.strokeIDs,
                                    elements: JSONCoding.encode([ElementValue]()), note: PageInkConflict.mergedNote))
        do {
            let merged = try ink.merge(baseStrokeIDs: baseStrokeIDs, ours: ours, theirs: theirs)
            write(merged, to: page, now: now)
            try context.save()
            return .merged(merged)
        } catch {
            context.insert(PageRevision(pageID: page.id, notebookID: page.notebookID, reason: .conflict, createdAt: now,
                                        inkData: theirs.data, strokeIDs: theirs.strokeIDs,
                                        elements: JSONCoding.encode([ElementValue]()),
                                        note: "\(PageInkConflict.unmergeableNote) (\(error.localizedDescription))"))
            write(ours, to: page, now: now)
            try context.save()
            return .keptLocal
        }
    }

    private func write(_ ink: InkState, to page: Page, now: Date) {
        page.inkData = ink.data
        page.strokeIDs = ink.strokeIDs
        page.inkHash = ink.data.map(Hashing.sha256Hex) ?? ""
        markDirty(page, fields: ["inkData", "strokeIDs", "inkHash"], now: now)
    }
}
