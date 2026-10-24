import SwiftUI
import Testing
import SheafnoteCore
@testable import Sheafnote

@MainActor
@Suite struct TapeAndSelectionTests {
    private func addTape(_ page: PageSession, at frame: CGRect, revealed: Bool = false) throws -> ElementValue {
        try page.elements.add(ElementValue(pageID: page.pageID, kind: .tape, frame: frame,
                                           payload: PayloadCodec.encode(TapePayload(colorHex: "#FF0000", isRevealed: revealed))), undoName: "Add")
    }

    private func isRevealed(_ page: PageSession, _ id: UUID) -> Bool? {
        page.elementValues.first { $0.id == id }?.decoded(TapePayload.self)?.isRevealed
    }

    @Test func togglingFlipsStateAndUndoRestoresIt() async throws {
        let f = try ElementsFixture()
        let page = try f.page()
        let tape = try addTape(page, at: CGRect(x: 10, y: 10, width: 100, height: 20))
        await EditorFixture.settle()
        TapeToggling.toggle(tape, on: page, editor: f.session)
        #expect(isRevealed(page, tape.id) == true)
        // A stale copy of the element must not set the same state twice.
        await EditorFixture.settle()
        TapeToggling.toggle(tape, on: page, editor: f.session)
        #expect(isRevealed(page, tape.id) == false)
        await EditorFixture.settle()
        f.session.undo()
        #expect(isRevealed(page, tape.id) == true)
    }

    @Test func hideAllAndShowAllChangeOnlyTapes() async throws {
        let f = try ElementsFixture()
        let page = try f.page()
        let a = try addTape(page, at: CGRect(x: 10, y: 10, width: 100, height: 20), revealed: true)
        let b = try addTape(page, at: CGRect(x: 10, y: 50, width: 100, height: 20), revealed: false)
        let sticker = try f.inserter.insertSticker(try #require(StickerCatalog.sticker(id: "star")))
        await EditorFixture.settle()
        let stickerBefore = sticker.payload
        for changed in StudyTape.settingRevealed(false, in: page.elementValues) {
            try page.elements.update(id: changed.id, undoName: "Hide") { $0.payload = changed.payload }
        }
        #expect(isRevealed(page, a.id) == false && isRevealed(page, b.id) == false)
        #expect(page.elementValues.first { $0.id == sticker.id }?.payload == stickerBefore)
        #expect(StudyTape.allCovering(in: page.elementValues))
    }

    @Test func tapeToolLaysTapeThatCoversInk() async throws {
        let f = try ElementsFixture()
        let page = try f.page()
        let swatch = StudyTape.swatches[2]
        let rect = try #require(StudyTape.rect(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 300, y: 118), pageSize: page.pageSize))
        let element = StudyTape.element(pageID: page.pageID, rect: rect, swatch: swatch, zIndex: 0)
        try page.elements.add(element, undoName: "Add Tape")
        let renderer = try #require(f.host.elementRenderers.renderer(for: .tape))
        #expect(renderer.slot == .aboveInk)
        let bitmap = try await f.pixels(of: element)
        #expect(bitmap.alpha(x: 200, y: 108) == 255)
    }

    @Test func topElementPrefersTapeThenZOrder() throws {
        let f = try ElementsFixture()
        let page = try f.page()
        let low = try f.inserter.insertSticker(try #require(StickerCatalog.sticker(id: "circle")))
        let high = try f.inserter.insertSticker(try #require(StickerCatalog.sticker(id: "square")))
        let point = CGPoint(x: low.frame.midX, y: low.frame.midY)
        #expect(ElementSelecting.topElement(at: point, on: page, host: f.host)?.id == high.id)
        let tape = try addTape(page, at: low.frame.insetBy(dx: 10, dy: 10))
        #expect(ElementSelecting.topElement(at: point, on: page, host: f.host)?.id == tape.id)
        #expect(ElementSelecting.topElement(at: point, on: page, host: f.host, kinds: [.sticker])?.id == high.id)
        #expect(ElementSelecting.topElement(at: CGPoint(x: 1, y: 1), on: page, host: f.host) == nil)
    }

    @Test func selectingAnElementSetsTheSharedSelection() throws {
        let f = try ElementsFixture()
        let page = try f.page()
        let sticker = try f.inserter.insertSticker(try #require(StickerCatalog.sticker(id: "heart")))
        #expect(f.session.selection.elementIDs == [sticker.id])
        #expect(f.session.selection.pageID == page.pageID)
        #expect(f.session.selection.bounds == OrientedBoxHitTester(element: sticker).bounds)
        #expect(ElementSelecting.selectedElement(on: page, editor: f.session)?.id == sticker.id)
        f.session.selection.clear()
        #expect(ElementSelecting.selectedElement(on: page, editor: f.session) == nil)
    }

    @Test func movingAStickerThroughTheEditorKeepsItsPayload() throws {
        let f = try ElementsFixture()
        let page = try f.page()
        let sticker = try f.inserter.insertSticker(try #require(StickerCatalog.sticker(id: "heart")))
        try f.session.transformer.apply(CGAffineTransform(translationX: 40, y: 25), to: f.session.selection, in: page)
        let moved = try #require(page.elementValues.first { $0.id == sticker.id })
        #expect(moved.frame.origin == CGPoint(x: sticker.frame.minX + 40, y: sticker.frame.minY + 25))
        #expect(moved.payload == sticker.payload)
    }

    @Test func zOrderMovesElementsToFrontAndBack() throws {
        let f = try ElementsFixture()
        let page = try f.page()
        let a = try f.inserter.insertSticker(try #require(StickerCatalog.sticker(id: "circle")))
        let b = try f.inserter.insertSticker(try #require(StickerCatalog.sticker(id: "square")))
        try f.inserter.moveToBack(b)
        let z = { (id: UUID) in page.elementValues.first { $0.id == id }!.zIndex }
        #expect(z(b.id) < z(a.id))
        try f.inserter.moveToFront(b)
        #expect(z(b.id) > z(a.id))
    }
}
