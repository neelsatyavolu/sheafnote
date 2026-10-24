import Testing
import SheafnoteCore
@testable import Sheafnote

@MainActor
@Suite struct PageOperationTests {
    @Test func addPageAfterCurrentThenUndoAndRedo() async throws {
        let f = try EditorFixture(pages: 2)
        let first = f.session.pageIDs[0], second = f.session.pageIDs[1]
        let added = try #require(f.session.addPage(.after(first), template: TemplateSpec(kind: .gridSmall)))
        #expect(f.session.pageIDs == [first, added, second])
        #expect(f.session.currentPageID == added)
        #expect(f.services.pages.page(id: added)?.template?.kind == .gridSmall)

        await EditorFixture.settle()
        f.session.undo()
        #expect(f.session.pageIDs == [first, second])
        #expect(f.session.canRedo)
        f.session.redo()
        #expect(f.session.pageIDs == [first, added, second])
    }

    @Test func addBeforeAndAtEnd() throws {
        let f = try EditorFixture(pages: 2)
        let first = f.session.pageIDs[0], second = f.session.pageIDs[1]
        let before = try #require(f.session.addPage(.before(first), template: nil))
        let end = try #require(f.session.addPage(.end, template: nil, paperColor: .yellow))
        #expect(f.session.pageIDs == [before, first, second, end])
        #expect(f.services.pages.page(id: end)?.paperColorOverrideValue == .yellow)
    }

    @Test func duplicateCopiesInkAndSitsAfterTheOriginal() async throws {
        let f = try EditorFixture(pages: 2)
        let page = try f.page()
        page.setDrawing(PKDrawingFactory.one(), undoName: "Draw")
        page.flush()
        f.session.duplicatePages([page.pageID])
        #expect(f.session.pageIDs.count == 3)
        let copyID = f.session.pageIDs[1]
        #expect(copyID != page.pageID)
        #expect(f.services.pages.page(id: copyID)?.inkData == f.services.pages.page(id: page.pageID)?.inkData)
        await EditorFixture.settle()
        f.session.undo()
        #expect(f.session.pageIDs.count == 2)
    }

    @Test func deleteIsReversibleAndSnapshotsFirst() async throws {
        let f = try EditorFixture(pages: 3)
        let ids = f.session.pageIDs
        f.session.deletePages([ids[1]])
        #expect(f.session.pageIDs == [ids[0], ids[2]])
        #expect(f.services.revisions.revisions(for: ids[1]).count == 1)
        #expect(f.services.pages.page(id: ids[1])?.deletedAt != nil)   // soft delete: the row is still there
        await EditorFixture.settle()
        f.session.undo()
        #expect(f.session.pageIDs == ids)
        #expect(f.services.pages.page(id: ids[1])?.deletedAt == nil)
    }

    @Test func aNotebookKeepsAtLeastOnePage() throws {
        let f = try EditorFixture(pages: 2)
        let ids = f.session.pageIDs
        f.session.deletePages(ids)
        #expect(f.session.pageIDs == ids)
        #expect(f.session.toast != nil)
    }

    @Test func deletingTheCurrentPageMovesTheCurrentPage() throws {
        let f = try EditorFixture(pages: 3)
        let ids = f.session.pageIDs
        f.session.goToPage(id: ids[1], animated: false)
        f.session.deletePages([ids[1]])
        #expect(f.session.currentPageID != ids[1])
        #expect(f.session.currentPageID.map { f.session.pageIDs.contains($0) } == true)
    }

    @Test func reorderUsesFractionalKeysAndUndoes() async throws {
        let f = try EditorFixture(pages: 3)
        let ids = f.session.pageIDs
        let keysBefore = ids.compactMap { f.services.pages.page(id: $0)?.sortKey }
        f.session.movePage(ids[2], relativeTo: ids[0], after: false)
        #expect(f.session.pageIDs == [ids[2], ids[0], ids[1]])
        // Only the moved page got a new key.
        #expect(f.services.pages.page(id: ids[0])?.sortKey == keysBefore[0])
        #expect(f.services.pages.page(id: ids[1])?.sortKey == keysBefore[1])
        #expect(f.services.pages.page(id: ids[2])?.sortKey != keysBefore[2])
        await EditorFixture.settle()
        f.session.undo()
        #expect(f.session.pageIDs == ids)
        f.session.redo()
        #expect(f.session.pageIDs == [ids[2], ids[0], ids[1]])
    }

    @Test func movingBetweenNeighboursAfterTarget() throws {
        let f = try EditorFixture(pages: 4)
        let ids = f.session.pageIDs
        f.session.movePage(ids[0], relativeTo: ids[2], after: true)
        #expect(f.session.pageIDs == [ids[1], ids[2], ids[0], ids[3]])
        f.session.movePage(ids[0], relativeTo: ids[0], after: true)   // onto itself: no-op
        #expect(f.session.pageIDs == [ids[1], ids[2], ids[0], ids[3]])
    }

    @Test func changeTemplateForOnePageAndAllPagesThenUndo() async throws {
        let f = try EditorFixture(pages: 2)
        let ids = f.session.pageIDs
        f.session.changeTemplate(pageIDs: [ids[0]], template: TemplateSpec(kind: .dotted), paperColor: .yellow)
        #expect(f.services.pages.page(id: ids[0])?.template?.kind == .dotted)
        #expect(f.services.pages.page(id: ids[0])?.paperColorOverrideValue == .yellow)
        #expect(f.services.pages.page(id: ids[1])?.template == nil)
        await EditorFixture.settle()
        f.session.undo()
        #expect(f.services.pages.page(id: ids[0])?.template == nil)
        #expect(f.services.pages.page(id: ids[0])?.paperColorOverride == nil)

        f.session.changeTemplate(pageIDs: ids, template: TemplateSpec(kind: .cornell), paperColor: .dark)
        #expect(ids.allSatisfy { f.services.pages.page(id: $0)?.template?.kind == .cornell })
    }

    @Test func templateChangeRefreshesLivePageSnapshot() throws {
        let f = try EditorFixture()
        let page = try f.page()
        let before = page.layersRevision
        f.session.changeTemplate(pageIDs: [page.pageID], template: TemplateSpec(kind: .gridLarge), paperColor: .white)
        #expect(page.snapshot.template.kind == .gridLarge)
        #expect(page.layersRevision > before)
    }

    @Test func goToPageByNumber() throws {
        let f = try EditorFixture(pages: 3)
        f.session.goToPage(number: 3)
        #expect(f.session.currentPageID == f.session.pageIDs[2])
        f.session.goToPage(number: 9)
        #expect(f.session.toast != nil)
        #expect(f.session.currentPageNumber == 3)
    }

    @Test func scrollDirectionIsStoredOnTheNotebook() throws {
        let f = try EditorFixture()
        let revision = f.session.layoutRevision
        f.session.setScrollDirection(.horizontal)
        #expect(f.notebook.scrollDirectionValue == .horizontal)
        #expect(f.notebook.syncDirty && f.notebook.dirtyFields.contains("scrollDirection"))
        #expect(f.session.layoutRevision > revision)
    }

    @Test func largeNotebooksOnlyHoldLivePagesOnDemand() throws {
        let f = try EditorFixture(pages: 300)
        #expect(f.session.pageIDs.count == 300)
        #expect(f.session.pageSessions.isEmpty)
        let ids = (0..<5).map { f.session.pageIDs[$0 * 10] }
        for id in ids { _ = f.session.pageSession(for: id) }
        #expect(f.session.pageSessions.count == 5)
        let page = try #require(f.session.pageSession(for: ids[0]))
        page.setDrawing(PKDrawingFactory.one(), undoName: "Draw")
        f.session.releasePage(id: ids[0])
        #expect(f.session.pageSessions.count == 4)
        #expect(f.services.pages.page(id: ids[0])?.inkData != nil)   // released pages are flushed first
    }
}
