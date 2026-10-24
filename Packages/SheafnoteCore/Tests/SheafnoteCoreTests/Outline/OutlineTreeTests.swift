import XCTest
@testable import SheafnoteCore

final class OutlineTreeTests: XCTestCase {
    private func item(_ title: String, key: String, parent: UUID? = nil, id: UUID = UUID(), page: UUID? = nil,
                      pdfIndex: Int? = nil, source: OutlineSource = .user) -> OutlineItem {
        OutlineItem(id: id, title: title, pageID: page, pdfPageIndex: pdfIndex, parentID: parent, sortKey: key, source: source)
    }

    func testDepthFirstOrderWithSiblingsBySortKey() {
        let root = UUID()
        let items = [
            item("B", key: "b"),
            item("A child 2", key: "b", parent: root),
            item("A", key: "a", id: root),
            item("A child 1", key: "a", parent: root),
        ]
        let rows = OutlineTree.rows(from: items)
        XCTAssertEqual(rows.map(\.item.title), ["A", "A child 1", "A child 2", "B"])
        XCTAssertEqual(rows.map(\.depth), [0, 1, 1, 0])
    }

    func testOrphansBecomeTopLevel() {
        let rows = OutlineTree.rows(from: [item("Lost", key: "a", parent: UUID())])
        XCTAssertEqual(rows.map(\.depth), [0])
    }

    func testCyclesDoNotLoopOrLoseEntries() {
        let a = UUID(), b = UUID()
        let rows = OutlineTree.rows(from: [item("A", key: "a", parent: b, id: a), item("B", key: "a", parent: a, id: b)])
        XCTAssertEqual(Set(rows.map(\.item.title)), ["A", "B"])
        XCTAssertEqual(rows.count, 2)
    }

    func testResolvesNotebookPageDirectlyOrThroughPdfIndex() {
        let p0 = UUID(), p1 = UUID()
        let pages = [OutlinePageRef(id: p0, pdfPageIndex: 0), OutlinePageRef(id: p1, pdfPageIndex: 1)]
        XCTAssertEqual(OutlineTree.targetPage(of: item("x", key: "a", page: p1), in: pages), p1)
        XCTAssertEqual(OutlineTree.targetPage(of: item("x", key: "a", pdfIndex: 1, source: .pdf), in: pages), p1)
        XCTAssertNil(OutlineTree.targetPage(of: item("x", key: "a", pdfIndex: 9, source: .pdf), in: pages))
        XCTAssertNil(OutlineTree.targetPage(of: item("x", key: "a", page: UUID()), in: pages))
    }

    func testDirectPageWinsWhenBothArePresentButStale() {
        let live = UUID()
        let pages = [OutlinePageRef(id: live, pdfPageIndex: 3)]
        let entry = item("x", key: "a", page: UUID(), pdfIndex: 3, source: .pdf)
        XCTAssertEqual(OutlineTree.targetPage(of: entry, in: pages), live)
    }

    func testDescendantsCoverTheWholeBranch() {
        let root = UUID(), child = UUID()
        let items = [item("r", key: "a", id: root), item("c", key: "a", parent: root, id: child),
                     item("g", key: "a", parent: child), item("other", key: "b")]
        XCTAssertEqual(OutlineTree.descendantIDs(of: root, in: items).count, 2)
    }
}
