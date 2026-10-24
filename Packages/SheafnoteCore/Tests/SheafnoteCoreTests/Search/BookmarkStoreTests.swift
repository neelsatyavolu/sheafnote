import SwiftData
import XCTest
@testable import SheafnoteCore

@MainActor
final class BookmarkStoreTests: XCTestCase {
    private var fixture: StoreFixture?
    private func setup(pages: Int = 3) throws -> (StoreFixture, Notebook, [UUID], BookmarkStore) {
        let f = try StoreFixture()
        fixture = f
        let nb = try f.notebook()
        for _ in 1..<pages { try f.pages.addPage(to: nb.id, at: .end, template: nil) }
        let ids = try f.pages.orderedPages(of: nb.id).map(\.id)
        return (f, nb, ids, BookmarkStore(context: f.context))
    }

    func testToggleAddsThenRemoves() throws {
        let (_, nb, ids, store) = try setup()
        XCTAssertFalse(try store.isBookmarked(pageID: ids[0]))
        XCTAssertTrue(try store.toggle(pageID: ids[0], notebookID: nb.id))
        XCTAssertTrue(try store.isBookmarked(pageID: ids[0]))
        XCTAssertFalse(try store.toggle(pageID: ids[0], notebookID: nb.id))
        XCTAssertFalse(try store.isBookmarked(pageID: ids[0]))
    }

    func testRemovingKeepsTheRowAsATombstoneAndReAddingRevivesIt() throws {
        let (f, nb, ids, store) = try setup()
        try store.toggle(pageID: ids[1], notebookID: nb.id)
        try store.toggle(pageID: ids[1], notebookID: nb.id)
        XCTAssertEqual(try f.context.fetch(FetchDescriptor<Bookmark>()).count, 1)
        try store.toggle(pageID: ids[1], notebookID: nb.id)
        XCTAssertEqual(try f.context.fetch(FetchDescriptor<Bookmark>()).count, 1)
        XCTAssertEqual(try store.bookmarks(in: nb.id, pageOrder: ids).count, 1)
    }

    func testListFollowsPageOrderNotCreationOrder() throws {
        let (_, nb, ids, store) = try setup()
        try store.toggle(pageID: ids[2], notebookID: nb.id, now: Date(timeIntervalSince1970: 1))
        try store.toggle(pageID: ids[0], notebookID: nb.id, now: Date(timeIntervalSince1970: 2))
        XCTAssertEqual(try store.bookmarks(in: nb.id, pageOrder: ids).map(\.pageID), [ids[0], ids[2]])
    }

    func testOrderingPutsBookmarksOfMissingPagesLast() {
        let a = UUID(), b = UUID()
        let items = [BookmarkItem(id: UUID(), pageID: UUID(), title: nil, createdAt: .distantPast),
                     BookmarkItem(id: UUID(), pageID: b, title: nil, createdAt: .now),
                     BookmarkItem(id: UUID(), pageID: a, title: nil, createdAt: .now)]
        let sorted = BookmarkOrdering.sorted(items, pageOrder: [a, b])
        XCTAssertEqual(sorted.prefix(2).map(\.pageID), [a, b])
    }

    func testRenameTrimsAndClearsEmptyTitles() throws {
        let (_, nb, ids, store) = try setup()
        try store.toggle(pageID: ids[0], notebookID: nb.id)
        let id = try XCTUnwrap(try store.bookmarks(in: nb.id, pageOrder: ids).first).id
        try store.rename(id: id, to: "  Key proof ")
        XCTAssertEqual(try store.bookmarks(in: nb.id, pageOrder: ids).first?.title, "Key proof")
        try store.rename(id: id, to: "   ")
        XCTAssertNil(try store.bookmarks(in: nb.id, pageOrder: ids).first?.title)
        XCTAssertThrowsError(try store.rename(id: UUID(), to: "x"))
    }

    func testBookmarkMarksRecordDirtyForSync() throws {
        let (f, nb, ids, store) = try setup()
        try store.toggle(pageID: ids[0], notebookID: nb.id)
        let row = try XCTUnwrap(try f.context.fetch(FetchDescriptor<Bookmark>()).first)
        XCTAssertTrue(row.syncDirty)
    }

    func testRemoveByID() throws {
        let (_, nb, ids, store) = try setup()
        try store.toggle(pageID: ids[0], notebookID: nb.id)
        let id = try XCTUnwrap(try store.bookmarks(in: nb.id, pageOrder: ids).first).id
        try store.remove(id: id)
        XCTAssertTrue(try store.bookmarks(in: nb.id, pageOrder: ids).isEmpty)
    }
}
