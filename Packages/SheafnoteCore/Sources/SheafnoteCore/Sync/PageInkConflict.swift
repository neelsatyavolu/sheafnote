import Foundation
import SwiftData

/// Ink conflict flow for a page that has unsent ink changes when a server version arrives (design 4.3).
///
/// 1. Ink not changed locally: take the server's ink.
/// 2. Both sides hold the same ink: nothing to merge.
/// 3. Otherwise snapshot OURS into the Recovered area, then three-way merge per stroke. A missing base (page never
///    synced from this device) is treated as empty, which unions both sides, so nothing is dropped.
/// 4. If the merge throws (corrupt or undecodable ink): ours stays live and THEIRS is stored as a conflict
///    revision for 30 days. Ink is never dropped silently.
@MainActor
enum PageInkConflict {
    struct Result {
        /// Non-nil when the outcome differs from a plain merge.
        var outcome: ApplyOutcome?
        /// True when the local ink still has to be uploaded.
        var inkStillDirty: Bool
    }

    static let mergedNote = "Your version before it was merged with the iCloud version."
    static let unmergeableNote = "iCloud version of this page, kept because it could not be merged with yours."

    static func resolve(_ page: Page, server r: SyncRecord, ink: any InkMerging, in context: ModelContext,
                        now: Date) throws -> Result {
        let theirs = InkState(data: r.bytes("inkData"), strokeIDs: r.strings("strokeIDs") ?? [])
        let inkChangedLocally = !Set(page.dirtyFields).isDisjoint(with: Page.inkFields)
        guard inkChangedLocally else {
            page.inkData = theirs.data
            page.strokeIDs = theirs.strokeIDs
            page.inkHash = r.string("inkHash") ?? ""
            page.adoptServerInkAsBase()
            return Result(outcome: nil, inkStillDirty: false)
        }
        if (r.string("inkHash") ?? "") == page.inkHash && theirs.strokeIDs == page.strokeIDs {
            page.baseInkData = theirs.data
            page.baseStrokeIDs = theirs.strokeIDs
            return Result(outcome: nil, inkStillDirty: false)
        }
        if theirs.strokeIDs == page.baseStrokeIDs && theirs.data == page.baseInkData {
            // The server still has the version we last synced (for example an echo of our own save): nothing to merge.
            return Result(outcome: nil, inkStillDirty: true)
        }
        let ours = InkState(data: page.inkData, strokeIDs: page.strokeIDs)
        try RevisionStore(context: context).snapshot(page: page, reason: .conflict, note: mergedNote, now: now)
        let baseIDs = page.baseStrokeIDs
        page.baseInkData = theirs.data
        page.baseStrokeIDs = theirs.strokeIDs
        do {
            let merged = try ink.merge(baseStrokeIDs: baseIDs, ours: ours, theirs: theirs)
            page.inkData = merged.data
            page.strokeIDs = merged.strokeIDs
            page.inkHash = merged.data.map(Hashing.sha256Hex) ?? ""
            return Result(outcome: nil, inkStillDirty: true)
        } catch {
            context.insert(PageRevision(pageID: page.id, notebookID: page.notebookID, reason: .conflict, createdAt: now,
                                        inkData: theirs.data, strokeIDs: theirs.strokeIDs,
                                        elements: JSONCoding.encode([ElementValue]()),
                                        note: "\(unmergeableNote) (\(error.localizedDescription))"))
            return Result(outcome: .keptBothVersions, inkStillDirty: true)
        }
    }
}
