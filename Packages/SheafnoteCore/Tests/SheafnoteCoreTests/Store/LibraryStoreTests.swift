import Foundation
import SwiftData
import Testing
@testable import SheafnoteCore

@MainActor
@Suite struct LibraryStoreTests {
    @Test func createNotebookMakesFirstPage() throws {
        let f = try StoreFixture()
        let nb = try f.notebook("Physics")
        #expect(nb.title == "Physics")
        #expect(nb.syncDirty && !nb.dirtyFields.isEmpty)
        let pages = try f.pages.orderedPages(of: nb.id)
        #expect(pages.count == 1)
        #expect(pages[0].size == PaperSize.a4.portraitSize)
        #expect(!pages[0].isInfinite)
    }

    @Test func whiteboardGetsInfinitePageAndTextGetsNone() throws {
        let f = try StoreFixture()
        let wb = try f.notebook("Board", kind: .whiteboard)
        let text = try f.notebook("Doc", kind: .text)
        #expect(try f.pages.orderedPages(of: wb.id).first?.isInfinite == true)
        #expect(try f.pages.orderedPages(of: text.id).isEmpty)
    }

    @Test func notebookAccessorsRoundTrip() throws {
        let f = try StoreFixture()
        let nb = try f.library.createNotebook(title: "A", kind: .paged, cover: CoverSpec(coverID: "tide"),
                                              template: TemplateSpec(kind: .cornell), paperSize: .letter,
                                              orientation: .landscape, paperColor: .yellow, in: nil)
        #expect(nb.cover.coverID == "tide")
        #expect(nb.template.kind == .cornell)
        #expect(nb.paperSizeValue == .letter && nb.orientationValue == .landscape && nb.paperColorValue == .yellow)
        #expect(nb.pageSize == CGSize(width: 792, height: 612))
    }

    @Test func foldersNestAndAppendInOrder() throws {
        let f = try StoreFixture()
        let a = try f.library.createFolder(name: "A", in: nil)
        let b = try f.library.createFolder(name: "B", in: nil)
        let c = try f.library.createFolder(name: "C", in: a.id)
        #expect(a.sortKey < b.sortKey)
        #expect(c.parentID == a.id)
    }

    @Test func renameTrimsAndRejectsEmpty() throws {
        let f = try StoreFixture()
        let nb = try f.notebook()
        try f.library.rename(.notebook(nb.id), to: "  New  ")
        #expect(nb.title == "New")
        #expect(throws: StoreError.self) { try f.library.rename(.notebook(nb.id), to: "   ") }
        #expect(nb.title == "New")
    }

    @Test func favoriteAndCover() throws {
        let f = try StoreFixture()
        let nb = try f.notebook()
        let folder = try f.library.createFolder(name: "F", in: nil)
        try f.library.setFavorite([.notebook(nb.id), .folder(folder.id)], true)
        #expect(nb.isFavorite && folder.isFavorite)
        try f.library.setCover(nb.id, to: CoverSpec(coverID: "orbit"))
        #expect(nb.cover.coverID == "orbit")
        #expect(nb.dirtyFields.contains("coverSpec"))
    }

    @Test func moveBetweenFolders() throws {
        let f = try StoreFixture()
        let folder = try f.library.createFolder(name: "F", in: nil)
        let nb = try f.notebook()
        try f.library.move([.notebook(nb.id)], to: folder.id)
        #expect(nb.folderID == folder.id)
        try f.library.move([.notebook(nb.id)], to: nil)
        #expect(nb.folderID == nil)
    }

    @Test func cannotMoveFolderIntoItselfOrDescendant() throws {
        let f = try StoreFixture()
        let a = try f.library.createFolder(name: "A", in: nil)
        let b = try f.library.createFolder(name: "B", in: a.id)
        #expect(throws: StoreError.self) { try f.library.move([.folder(a.id)], to: a.id) }
        #expect(throws: StoreError.self) { try f.library.move([.folder(a.id)], to: b.id) }
        #expect(a.parentID == nil)
    }

    @Test func cannotMoveIntoDeletedFolder() throws {
        let f = try StoreFixture()
        let a = try f.library.createFolder(name: "A", in: nil)
        let nb = try f.notebook()
        try f.library.softDelete([.folder(a.id)])
        #expect(throws: StoreError.self) { try f.library.move([.notebook(nb.id)], to: a.id) }
    }

    @Test func softDeleteKeepsDataAndRestoreBringsItBack() throws {
        let f = try StoreFixture()
        let nb = try f.notebook()
        let page = try #require(try f.pages.orderedPages(of: nb.id).first)
        try f.pages.saveInk(pageID: page.id, drawingData: Data([1, 2, 3]), strokeIDs: [StrokeID(rawValue: "s1")])
        try f.library.softDelete([.notebook(nb.id)])
        #expect(nb.deletedAt != nil)
        #expect(f.pages.inkData(pageID: page.id) == Data([1, 2, 3]))
        try f.library.restore([.notebook(nb.id)])
        #expect(nb.deletedAt == nil)
    }

    @Test func deletingFolderCarriesContentsAndRestoreReturnsThem() throws {
        let f = try StoreFixture()
        let outer = try f.library.createFolder(name: "Outer", in: nil)
        let inner = try f.library.createFolder(name: "Inner", in: outer.id)
        let a = try f.notebook("A", in: outer.id)
        let b = try f.notebook("B", in: inner.id)
        let earlier = try f.notebook("Earlier", in: outer.id)
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        try f.library.softDelete([.notebook(earlier.id)], now: t0)
        try f.library.softDelete([.folder(outer.id)], now: t0 + 100)
        #expect(a.deletedAt == t0 + 100 && b.deletedAt == t0 + 100 && inner.deletedAt == t0 + 100)
        #expect(earlier.deletedAt == t0)
        try f.library.restore([.folder(outer.id)])
        #expect(outer.deletedAt == nil && inner.deletedAt == nil && a.deletedAt == nil && b.deletedAt == nil)
        #expect(earlier.deletedAt == t0)   // deleted separately, stays in the trash
    }

    @Test func restoreMovesToTopLevelWhenParentStillDeleted() throws {
        let f = try StoreFixture()
        let folder = try f.library.createFolder(name: "F", in: nil)
        let nb = try f.notebook(in: folder.id)
        try f.library.softDelete([.notebook(nb.id)], now: Date(timeIntervalSince1970: 10))
        try f.library.softDelete([.folder(folder.id)], now: Date(timeIntervalSince1970: 20))
        try f.library.restore([.notebook(nb.id)])
        #expect(nb.deletedAt == nil)
        #expect(nb.folderID == nil)
    }

    @Test func purgeBoundaryIsThirtyDays() throws {
        let f = try StoreFixture()
        let now = Date(timeIntervalSince1970: 100 * day)
        let exactly = try f.notebook("Exactly30")
        let older = try f.notebook("Older")
        let newer = try f.notebook("Newer")
        try f.library.softDelete([.notebook(exactly.id)], now: now - 30 * day)
        try f.library.softDelete([.notebook(older.id)], now: now - 30 * day - 1)
        try f.library.softDelete([.notebook(newer.id)], now: now - 29 * day)
        let olderID = older.id
        var purged: [PurgedRecord] = []
        f.library.onPurge = { purged = $0 }
        #expect(try f.library.purgeExpired(now: now) == 1)
        #expect(f.library.notebook(id: olderID) == nil)
        #expect(f.library.notebook(id: exactly.id) != nil)
        #expect(f.library.notebook(id: newer.id) != nil)
        #expect(purged.contains { $0.recordType == "SNNotebook" && $0.id == olderID })
        #expect(purged.contains { $0.recordType == "SNPage" })
    }

    @Test func purgeNeverTouchesLiveItems() throws {
        let f = try StoreFixture()
        let live = try f.notebook("Live", now: Date(timeIntervalSince1970: 0))
        _ = try f.library.purgeExpired(now: Date(timeIntervalSince1970: 1000 * day))
        #expect(f.library.notebook(id: live.id) != nil)
        #expect(try f.pages.orderedPages(of: live.id).count == 1)
    }

    @Test func purgeRemovesChildrenAndOrphanAssetsButKeepsSharedAssets() throws {
        let f = try StoreFixture()
        let a = try f.notebook("A"), b = try f.notebook("B")
        let shared = try f.pages.importAsset(data: Data([9, 9]), kind: .pdf, filename: "x.pdf")
        let only = try f.pages.importAsset(data: Data([8]), kind: .image, filename: nil)
        let pa = try #require(try f.pages.orderedPages(of: a.id).first)
        let pb = try #require(try f.pages.orderedPages(of: b.id).first)
        pa.backgroundAssetID = shared.id; pb.backgroundAssetID = shared.id
        try f.pages.insertElement(ElementValue(pageID: pa.id, kind: .image, frame: .zero, assetID: only.id))
        f.context.insert(Bookmark(notebookID: a.id, pageID: pa.id))
        let now = Date(timeIntervalSince1970: 500 * day)
        try f.library.softDelete([.notebook(a.id)], now: now - 40 * day)
        try f.library.purgeExpired(now: now)
        let assets = try f.context.fetch(FetchDescriptor<Asset>())
        #expect(assets.contains { $0.id == shared.id })
        #expect(!assets.contains { $0.id == only.id })
        #expect(try f.context.fetch(FetchDescriptor<PageElement>()).isEmpty)
        #expect(try f.context.fetch(FetchDescriptor<Bookmark>()).isEmpty)
        #expect(try f.pages.orderedPages(of: b.id).count == 1)
    }

    @Test func purgeRemovesOldSoftDeletedPagesOfLiveNotebook() throws {
        let f = try StoreFixture()
        let nb = try f.notebook()
        let extra = try f.pages.addPage(to: nb.id, at: .end, template: nil)
        let now = Date(timeIntervalSince1970: 300 * day)
        try f.pages.softDelete(pageIDs: [extra.id], now: now - 31 * day)
        try f.library.purgeExpired(now: now)
        #expect(f.pages.page(id: extra.id) == nil)
        #expect(try f.pages.orderedPages(of: nb.id).count == 1)
    }

    @Test func deletePermanentlyRequiresTrash() throws {
        let f = try StoreFixture()
        let nb = try f.notebook()
        #expect(throws: StoreError.self) { try f.library.deletePermanently([.notebook(nb.id)]) }
        #expect(f.library.notebook(id: nb.id) != nil)
        try f.library.softDelete([.notebook(nb.id)])
        #expect(try f.library.deletePermanently([.notebook(nb.id)]) == 1)
        #expect(f.library.notebook(id: nb.id) == nil)
    }

    @Test func deleteFolderPermanentlyRemovesSubtree() throws {
        let f = try StoreFixture()
        let outer = try f.library.createFolder(name: "O", in: nil)
        let inner = try f.library.createFolder(name: "I", in: outer.id)
        _ = try f.notebook("In", in: inner.id)
        try f.library.softDelete([.folder(outer.id)])
        #expect(try f.library.deletePermanently([.folder(outer.id)]) == 3)
        #expect(try f.library.allFolders().isEmpty && f.library.allNotebooks().isEmpty)
    }

    @Test func duplicateCopiesPagesInkElementsAndBookmarks() throws {
        let f = try StoreFixture()
        let nb = try f.notebook("Orig")
        let p1 = try #require(try f.pages.orderedPages(of: nb.id).first)
        let p2 = try f.pages.addPage(to: nb.id, at: .end, template: TemplateSpec(kind: .gridSmall))
        try f.pages.saveInk(pageID: p1.id, drawingData: Data([1]), strokeIDs: [StrokeID(rawValue: "a")])
        try f.pages.insertElement(ElementValue(pageID: p1.id, kind: .text, frame: CGRect(x: 1, y: 2, width: 3, height: 4)))
        f.context.insert(Bookmark(notebookID: nb.id, pageID: p2.id, title: "mark"))
        try f.context.save()
        let copy = try f.library.duplicate(nb)
        #expect(copy.id != nb.id && copy.title == "Orig copy")
        let cpages = try f.pages.orderedPages(of: copy.id)
        #expect(cpages.count == 2)
        #expect(cpages[0].inkData == Data([1]) && cpages[0].strokeIDs == ["a"])
        #expect(cpages[1].template?.kind == .gridSmall)
        #expect(try f.pages.elements(on: cpages[0].id).count == 1)
        #expect(try f.pages.elements(on: cpages[0].id)[0].id != (try f.pages.elements(on: p1.id))[0].id)
        let marks = try f.context.fetch(FetchDescriptor<Bookmark>()).filter { $0.notebookID == copy.id }
        #expect(marks.count == 1 && marks[0].pageID == cpages[1].id)
        #expect(f.pages.inkData(pageID: p1.id) == Data([1]))   // original untouched
    }

    @Test func recordOpenedDoesNotMarkDirty() throws {
        let f = try StoreFixture()
        let nb = try f.notebook()
        nb.syncDirty = false
        try f.library.recordOpened(nb.id)
        #expect(nb.lastOpenedAt != nil && !nb.syncDirty)
    }

    @Test func missingItemsThrowFriendlyErrors() throws {
        let f = try StoreFixture()
        #expect(throws: StoreError.self) { try f.library.rename(.folder(UUID()), to: "x") }
        let err = StoreError.notFound("the notebook")
        #expect(err.errorDescription?.contains("notebook") == true)
    }

    @Test func markDirtyPostsNotificationAndUnionsFields() throws {
        let f = try StoreFixture()
        let nb = try f.notebook()
        nb.dirtyFields = ["title"]
        var posted = false
        let token = NotificationCenter.default.addObserver(forName: .sheafnoteModelDidChange, object: nil, queue: nil) { _ in posted = true }
        markDirty(nb, fields: ["title", "isFavorite"])
        NotificationCenter.default.removeObserver(token)
        #expect(posted)
        #expect(Set(nb.dirtyFields) == ["title", "isFavorite"])
    }
}
