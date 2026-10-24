import SwiftData
import XCTest
@testable import SheafnoteCore

@MainActor
final class OutlineStoreTests: XCTestCase {
    private var fixture: StoreFixture?
    private func setup() throws -> (StoreFixture, Notebook, UUID, OutlineStore) {
        let f = try StoreFixture()
        fixture = f
        let nb = try f.notebook()
        let page = try XCTUnwrap(f.pages.orderedPages(of: nb.id).first)
        return (f, nb, page.id, OutlineStore(context: f.context))
    }

    private func titles(_ store: OutlineStore, _ nb: Notebook) throws -> [String] {
        OutlineTree.rows(from: try store.items(in: nb.id)).map { String(repeating: "-", count: $0.depth) + $0.item.title }
    }

    func testAddAppendsInOrderAndTrimsTitle() throws {
        let (_, nb, page, store) = try setup()
        try store.add(title: "  Intro ", pageID: page, notebookID: nb.id)
        try store.add(title: "Methods", pageID: page, notebookID: nb.id)
        XCTAssertEqual(try titles(store, nb), ["Intro", "Methods"])
        XCTAssertThrowsError(try store.add(title: "   ", pageID: page, notebookID: nb.id))
    }

    func testSubEntriesNestUnderParent() throws {
        let (_, nb, page, store) = try setup()
        let parent = try store.add(title: "Part 1", pageID: page, notebookID: nb.id)
        try store.add(title: "Chapter 1", pageID: page, notebookID: nb.id, parentID: parent.id)
        XCTAssertEqual(try titles(store, nb), ["Part 1", "-Chapter 1"])
    }

    func testRenameAndRetarget() throws {
        let (f, nb, page, store) = try setup()
        let entry = try store.add(title: "Old", pageID: page, notebookID: nb.id)
        try store.rename(id: entry.id, to: "New")
        let other = try f.pages.addPage(to: nb.id, at: .end, template: nil)
        try store.setTarget(id: entry.id, pageID: other.id)
        let item = try XCTUnwrap(try store.items(in: nb.id).first)
        XCTAssertEqual(item.title, "New")
        XCTAssertEqual(item.pageID, other.id)
        XCTAssertThrowsError(try store.rename(id: entry.id, to: ""))
    }

    func testRemoveKeepsChildrenAndSoftDeletes() throws {
        let (f, nb, page, store) = try setup()
        let parent = try store.add(title: "Parent", pageID: page, notebookID: nb.id)
        try store.add(title: "Child", pageID: page, notebookID: nb.id, parentID: parent.id)
        try store.remove(id: parent.id)
        XCTAssertEqual(try titles(store, nb), ["Child"])
        let rows = try f.context.fetch(FetchDescriptor<OutlineEntry>())
        XCTAssertEqual(rows.count, 2)
        XCTAssertNotNil(rows.first { $0.title == "Parent" }?.deletedAt)
    }

    func testMoveReordersSiblings() throws {
        let (_, nb, page, store) = try setup()
        let a = try store.add(title: "A", pageID: page, notebookID: nb.id)
        let b = try store.add(title: "B", pageID: page, notebookID: nb.id)
        let c = try store.add(title: "C", pageID: page, notebookID: nb.id)
        try store.move(id: c.id, toParent: nil, before: a.id)
        XCTAssertEqual(try titles(store, nb), ["C", "A", "B"])
        try store.move(id: c.id, toParent: nil, before: nil)
        XCTAssertEqual(try titles(store, nb), ["A", "B", "C"])
        try store.move(id: a.id, toParent: nil, before: c.id)
        XCTAssertEqual(try titles(store, nb), ["B", "A", "C"])
        _ = b
    }

    func testMoveIntoParentAndRefuseCycles() throws {
        let (_, nb, page, store) = try setup()
        let a = try store.add(title: "A", pageID: page, notebookID: nb.id)
        let b = try store.add(title: "B", pageID: page, notebookID: nb.id)
        try store.move(id: b.id, toParent: a.id, before: nil)
        XCTAssertEqual(try titles(store, nb), ["A", "-B"])
        XCTAssertThrowsError(try store.move(id: a.id, toParent: b.id, before: nil))
        XCTAssertThrowsError(try store.move(id: a.id, toParent: a.id, before: nil))
    }

    func testPdfEntriesAreSeparateFromUserEntries() throws {
        let (f, nb, page, store) = try setup()
        f.context.insert(OutlineEntry(notebookID: nb.id, title: "Chapter 1", pageID: nil, pdfPageIndex: 4, sortKey: "a", source: .pdf))
        try f.context.save()
        try store.add(title: "Mine", pageID: page, notebookID: nb.id)
        XCTAssertEqual(try store.items(in: nb.id, source: .pdf).map(\.title), ["Chapter 1"])
        XCTAssertEqual(try store.items(in: nb.id, source: .user).map(\.title), ["Mine"])
    }
}
