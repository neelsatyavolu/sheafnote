import Foundation
import SwiftData
import Testing
@testable import SheafnoteCore

@MainActor
@Suite("Reconciling an open editor with the store")
struct InkReconcileTests {
    private let ink = JSONInkMerging()

    private func state(_ strokes: [(String, Double)]) -> InkState {
        InkState(data: JSONInkMerging.data(strokes), strokeIDs: JSONInkMerging.ids(strokes))
    }

    /// A page the editor loaded with stroke "a", after which sync adopted a server version with "a" and "c".
    private func pageChangedBySync(_ f: SyncFixture) throws -> (page: Page, knownHash: String, base: [String]) {
        let page = try f.syncedPage(strokes: [("a", 1)])
        let known = page.inkHash, base = page.strokeIDs
        let theirs = state([("a", 1), ("c", 3)])
        page.inkData = theirs.data
        page.strokeIDs = theirs.strokeIDs
        page.inkHash = Hashing.sha256Hex(theirs.data ?? Data())
        page.adoptServerInkAsBase()
        try f.context.save()
        return (page, known, base)
    }

    @Test func unchangedStoreNeedsNothing() throws {
        let f = try SyncFixture()
        let page = try f.syncedPage(strokes: [("a", 1)])
        let outcome = try f.store.pages.reconcileInk(pageID: page.id, knownHash: page.inkHash, baseStrokeIDs: page.strokeIDs,
                                                     unsaved: state([("a", 1), ("z", 9)]), ink: ink)
        #expect(outcome == .unchanged)
        #expect(page.strokeIDs == ["a"])
    }

    @Test func remoteInkIsAdoptedWhenTheEditorHasNothingUnsaved() throws {
        let f = try SyncFixture()
        let (page, known, base) = try pageChangedBySync(f)
        let outcome = try f.store.pages.reconcileInk(pageID: page.id, knownHash: known, baseStrokeIDs: base, unsaved: nil, ink: ink)
        guard case .adopted(let adopted) = outcome else { Issue.record("expected adopted, got \(outcome)"); return }
        #expect(adopted.strokeIDs == ["a", "c"])
        #expect(page.strokeIDs == ["a", "c"])
        #expect(!page.syncDirty)
    }

    @Test func unsavedInkIsMergedWithRemoteInkAndSnapshotted() throws {
        let f = try SyncFixture()
        let (page, known, base) = try pageChangedBySync(f)
        let outcome = try f.store.pages.reconcileInk(pageID: page.id, knownHash: known, baseStrokeIDs: base,
                                                     unsaved: state([("a", 1), ("b", 2)]), ink: ink)
        guard case .merged(let merged) = outcome else { Issue.record("expected merged, got \(outcome)"); return }
        #expect(merged.strokeIDs == ["a", "b", "c"])
        #expect(page.strokeIDs == ["a", "b", "c"] && page.syncDirty)
        let revisions = try f.context.fetch(FetchDescriptor<PageRevision>())
        #expect(revisions.contains { $0.reasonValue == .conflict && $0.strokeIDs == ["a", "b"] })
    }

    @Test func unmergeableInkKeepsLocalAndStoresTheOtherVersion() throws {
        let f = try SyncFixture()
        let (page, known, base) = try pageChangedBySync(f)
        let outcome = try f.store.pages.reconcileInk(pageID: page.id, knownHash: known, baseStrokeIDs: base,
                                                     unsaved: state([("a", 1), ("b", 2)]), ink: UnavailableInkMerging())
        #expect(outcome == .keptLocal)
        #expect(page.strokeIDs == ["a", "b"])
        let revisions = try f.context.fetch(FetchDescriptor<PageRevision>())
        #expect(revisions.contains { $0.strokeIDs == ["a", "c"] })
        #expect(revisions.contains { $0.strokeIDs == ["a", "b"] })
    }
}
