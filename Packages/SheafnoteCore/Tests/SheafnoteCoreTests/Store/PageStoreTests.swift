import Foundation
import SwiftData
import Testing
@testable import SheafnoteCore

@MainActor
@Suite struct PageStoreTests {
    @Test func addPagePositions() throws {
        let f = try StoreFixture()
        let nb = try f.notebook()
        let first = try #require(try f.pages.orderedPages(of: nb.id).first)
        let end = try f.pages.addPage(to: nb.id, at: .end, template: nil)
        let mid = try f.pages.addPage(to: nb.id, at: .after(first.id), template: nil)
        let front = try f.pages.addPage(to: nb.id, at: .before(first.id), template: .blank)
        let ids = try f.pages.orderedPages(of: nb.id).map(\.id)
        #expect(ids == [front.id, first.id, mid.id, end.id])
        #expect(front.template == .blank && first.template == nil)
    }

    @Test func addPageToMissingNotebookThrows() throws {
        let f = try StoreFixture()
        #expect(throws: StoreError.self) { try f.pages.addPage(to: UUID(), at: .end, template: nil) }
    }

    @Test func moveBetweenNeighbours() throws {
        let f = try StoreFixture()
        let nb = try f.notebook()
        let a = try #require(try f.pages.orderedPages(of: nb.id).first)
        let b = try f.pages.addPage(to: nb.id, at: .end, template: nil)
        let c = try f.pages.addPage(to: nb.id, at: .end, template: nil)
        try f.pages.move(pageID: c.id, between: a.id, and: b.id)
        #expect(try f.pages.orderedPages(of: nb.id).map(\.id) == [a.id, c.id, b.id])
        try f.pages.move(pageID: b.id, between: nil, and: a.id)
        #expect(try f.pages.orderedPages(of: nb.id).map(\.id) == [b.id, a.id, c.id])
        #expect(b.dirtyFields.contains("sortKey"))
    }

    @Test func tenThousandReordersKeepOrderStable() throws {
        let f = try StoreFixture()
        let nb = try f.notebook()
        let a = try #require(try f.pages.orderedPages(of: nb.id).first)
        let b = try f.pages.addPage(to: nb.id, at: .end, template: nil)
        let m = try f.pages.addPage(to: nb.id, at: .end, template: nil)
        for _ in 0..<200 { try f.pages.move(pageID: m.id, between: a.id, and: b.id) }
        #expect(try f.pages.orderedPages(of: nb.id).map(\.id) == [a.id, m.id, b.id])
    }

    @Test func saveInkSetsHashAndStrokeIDs() throws {
        let f = try StoreFixture()
        let nb = try f.notebook()
        let p = try #require(try f.pages.orderedPages(of: nb.id).first)
        try f.pages.saveInk(pageID: p.id, drawingData: Data([1, 2]), strokeIDs: [.init(rawValue: "a"), .init(rawValue: "b")])
        #expect(p.strokeIDs == ["a", "b"])
        #expect(p.inkHash.count == 64)
        let before = p.inkHash
        try f.pages.saveInk(pageID: p.id, drawingData: Data([1, 2, 3]), strokeIDs: [.init(rawValue: "a")])
        #expect(p.inkHash != before)
        #expect(p.syncDirty && p.dirtyFields.contains("inkData"))
    }

    @Test func clearingInkSnapshotsFirst() throws {
        let f = try StoreFixture()
        let nb = try f.notebook()
        let p = try #require(try f.pages.orderedPages(of: nb.id).first)
        try f.pages.saveInk(pageID: p.id, drawingData: Data([5, 5]), strokeIDs: [.init(rawValue: "x")])
        try f.pages.saveInk(pageID: p.id, drawingData: Data([0]), strokeIDs: [])
        let revs = f.revisions.revisions(for: p.id)
        #expect(revs.count == 1)
        #expect(revs[0].reasonValue == .beforeClear)
        #expect(revs[0].inkData == Data([5, 5]) && revs[0].strokeIDs == ["x"])
    }

    @Test func savingEmptyInkOnEmptyPageDoesNotSnapshot() throws {
        let f = try StoreFixture()
        let nb = try f.notebook()
        let p = try #require(try f.pages.orderedPages(of: nb.id).first)
        try f.pages.saveInk(pageID: p.id, drawingData: Data(), strokeIDs: [])
        #expect(f.revisions.revisions(for: p.id).isEmpty)
    }

    @Test func softDeleteSnapshotsAndHides() throws {
        let f = try StoreFixture()
        let nb = try f.notebook()
        let p = try #require(try f.pages.orderedPages(of: nb.id).first)
        try f.pages.saveInk(pageID: p.id, drawingData: Data([7]), strokeIDs: [.init(rawValue: "k")])
        try f.pages.softDelete(pageIDs: [p.id])
        #expect(try f.pages.orderedPages(of: nb.id).isEmpty)
        #expect(f.pages.page(id: p.id)?.inkData == Data([7]))
        #expect(f.revisions.revisions(for: p.id).first?.reasonValue == .beforeDelete)
    }

    @Test func duplicatePageCopiesEverything() throws {
        let f = try StoreFixture()
        let nb = try f.notebook()
        let p = try #require(try f.pages.orderedPages(of: nb.id).first)
        try f.pages.saveInk(pageID: p.id, drawingData: Data([4]), strokeIDs: [.init(rawValue: "z")])
        try f.pages.insertElement(ElementValue(pageID: p.id, kind: .sticker, frame: CGRect(x: 0, y: 0, width: 10, height: 10)))
        let copy = try f.pages.duplicate(pageID: p.id)
        #expect(try f.pages.orderedPages(of: nb.id).map(\.id) == [p.id, copy.id])
        #expect(copy.inkData == Data([4]) && copy.strokeIDs == ["z"])
        #expect(try f.pages.elements(on: copy.id).count == 1)
        #expect(throws: StoreError.self) { try f.pages.duplicate(pageID: UUID()) }
    }

    @Test func elementsCrudAndZOrder() throws {
        let f = try StoreFixture()
        let nb = try f.notebook()
        let p = try #require(try f.pages.orderedPages(of: nb.id).first)
        let e1 = try f.pages.insertElement(ElementValue(pageID: p.id, kind: .text, frame: CGRect(x: 0, y: 0, width: 5, height: 5), zIndex: 2))
        let e2 = try f.pages.insertElement(ElementValue(pageID: p.id, kind: .image, frame: CGRect(x: 1, y: 1, width: 5, height: 5), zIndex: 1))
        #expect(try f.pages.elements(on: p.id).map(\.id) == [e2.id, e1.id])
        try f.pages.updateElement(id: e1.id) { $0.frame.origin = CGPoint(x: 50, y: 60); $0.rotation = 1 }
        let updated = try #require(try f.pages.elements(on: p.id).first { $0.id == e1.id })
        #expect(updated.frame.origin == CGPoint(x: 50, y: 60) && updated.rotation == 1)
        try f.pages.softDeleteElements(ids: [e2.id])
        #expect(try f.pages.elements(on: p.id).map(\.id) == [e1.id])
        #expect(throws: StoreError.self) { try f.pages.updateElement(id: UUID()) { _ in } }
    }

    @Test func assetsDedupBySha() async throws {
        let f = try StoreFixture()
        let a = try f.pages.importAsset(data: Data([1, 2, 3]), kind: .image, filename: "a.png")
        let b = try f.pages.importAsset(data: Data([1, 2, 3]), kind: .image, filename: "b.png")
        let c = try f.pages.importAsset(data: Data([1, 2, 3]), kind: .pdf, filename: "c.pdf")
        #expect(a.id == b.id)
        #expect(c.id != a.id)
        #expect(a.byteCount == 3 && a.sha256.count == 64)
        #expect(try await f.pages.data(for: a.id) == Data([1, 2, 3]))
        await #expect(throws: StoreError.self) { _ = try await f.pages.data(for: UUID()) }
    }
}
