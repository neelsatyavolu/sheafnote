import Foundation
import SwiftData
import Testing
@testable import SheafnoteCore

@MainActor
@Suite struct RevisionStoreTests {
    @Test func snapshotCapturesInkAndElements() throws {
        let f = try StoreFixture()
        let nb = try f.notebook()
        let p = try #require(try f.pages.orderedPages(of: nb.id).first)
        try f.pages.saveInk(pageID: p.id, drawingData: Data([3]), strokeIDs: [.init(rawValue: "s")])
        try f.pages.insertElement(ElementValue(pageID: p.id, kind: .text, frame: CGRect(x: 1, y: 1, width: 2, height: 2)))
        let rev = try f.revisions.snapshot(page: p, reason: .conflict, note: "theirs")
        #expect(rev.inkData == Data([3]) && rev.note == "theirs")
        #expect(JSONCoding.decode([ElementValue].self, from: rev.elements)?.count == 1)
        #expect(rev.expiresAt == rev.createdAt.addingTimeInterval(30 * day))
    }

    @Test func restoreCreatesNewPageAfterOriginalAndNeverOverwrites() throws {
        let f = try StoreFixture()
        let nb = try f.notebook()
        let a = try #require(try f.pages.orderedPages(of: nb.id).first)
        let b = try f.pages.addPage(to: nb.id, at: .end, template: nil)
        try f.pages.saveInk(pageID: a.id, drawingData: Data([1]), strokeIDs: [.init(rawValue: "old")])
        try f.pages.insertElement(ElementValue(pageID: a.id, kind: .text, frame: CGRect(x: 0, y: 0, width: 4, height: 4)))
        let rev = try f.revisions.snapshot(page: a, reason: .beforeClear)
        try f.pages.saveInk(pageID: a.id, drawingData: Data([2]), strokeIDs: [.init(rawValue: "new")])
        let restored = try f.revisions.restore(rev)
        #expect(try f.pages.orderedPages(of: nb.id).map(\.id) == [a.id, restored.id, b.id])
        #expect(restored.inkData == Data([1]) && restored.strokeIDs == ["old"])
        #expect(f.pages.inkData(pageID: a.id) == Data([2]))
        let els = try f.pages.elements(on: restored.id)
        #expect(els.count == 1 && els[0].pageID == restored.id)
        #expect(try f.pages.elements(on: a.id)[0].id != els[0].id)
    }

    @Test func restoreAppendsWhenOriginalGone() throws {
        let f = try StoreFixture()
        let nb = try f.notebook()
        let a = try #require(try f.pages.orderedPages(of: nb.id).first)
        try f.pages.saveInk(pageID: a.id, drawingData: Data([1]), strokeIDs: [.init(rawValue: "k")])
        let rev = try f.revisions.snapshot(page: a, reason: .beforeDelete)
        try f.pages.softDelete(pageIDs: [a.id])
        let restored = try f.revisions.restore(rev)
        #expect(try f.pages.orderedPages(of: nb.id).map(\.id) == [restored.id])
    }

    @Test func purgeOnlyExpired() throws {
        let f = try StoreFixture()
        let nb = try f.notebook()
        let p = try #require(try f.pages.orderedPages(of: nb.id).first)
        let base = Date(timeIntervalSince1970: 100 * day)
        let old = try f.revisions.snapshot(page: p, reason: .conflict, now: base)
        let fresh = try f.revisions.snapshot(page: p, reason: .conflict, now: base + 20 * day)
        #expect(try f.revisions.purgeExpired(now: base + 30 * day) == 0)
        #expect(try f.revisions.purgeExpired(now: base + 30 * day + 1) == 1)
        let left = try f.revisions.allRevisions().map(\.id)
        #expect(left == [fresh.id] && !left.contains(old.id))
    }
}
