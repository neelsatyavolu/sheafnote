import PencilKit
import SwiftUI
import Testing
import UIKit
import SheafnoteCore
@testable import Sheafnote

@MainActor
@Suite struct SelectionActionTests {
    func pageWithTwoStrokes(_ f: InkToolsFixture, pageIndex: Int = 0) throws -> PageSession {
        let page = try f.page(pageIndex)
        page.setDrawing(PKDrawing(strokes: [InkSketch.line(CGPoint(x: 100, y: 100), CGPoint(x: 200, y: 140)),
                                            InkSketch.line(CGPoint(x: 400, y: 300), CGPoint(x: 480, y: 360))]), undoName: "Draw")
        return page
    }

    func perform(_ id: String, _ f: InkToolsFixture, _ page: PageSession) async throws {
        try await f.action(id).perform(selection: f.session.selection, page: page, editor: f.session)
    }

    // MARK: Copy, cut, paste

    @Test func copyPutsOurTypeAndAPictureOnThePasteboard() async throws {
        let f = try InkToolsFixture()
        let page = try pageWithTwoStrokes(f)
        f.select([0], on: page)
        try await perform("ink.copy", f, page)
        let data = try #require(f.pasteboard.data(forPasteboardType: SelectionClipboard.pasteboardType))
        let clip = try #require(SelectionClipboard.decode(data))
        #expect(try PKDrawing(data: clip.strokes).strokes.count == 1)
        #expect(clip.sourcePageID == page.pageID && clip.bounds == f.session.selection.bounds)
        #expect(f.pasteboard.data(forPasteboardType: "public.png") != nil)
        #expect(page.drawing.strokes.count == 2, "copy must not change the page")
    }

    @Test func pasteOnTheSamePageLandsOffsetAndIsSelected() async throws {
        let f = try InkToolsFixture()
        let page = try pageWithTwoStrokes(f)
        f.select([0], on: page)
        let original = page.drawing.strokes[0].renderBounds
        try await perform("ink.copy", f, page)
        f.session.selection.clear()

        try f.clipboard.paste(into: page, editor: f.session)
        #expect(page.drawing.strokes.count == 3)
        let pasted = page.drawing.strokes[2].renderBounds
        #expect(abs(pasted.minX - (original.minX + PastePlacement.nudge)) < 0.01)
        #expect(f.session.selection.strokeIDs == [page.strokeIDs[2]])
        #expect(Set(page.strokeIDs).count == 3, "pasted ink must get its own stroke id")

        await InkToolsFixture.settle()
        try f.clipboard.paste(into: page, editor: f.session)
        let second = page.drawing.strokes[3].renderBounds
        #expect(abs(second.minX - (original.minX + 2 * PastePlacement.nudge)) < 0.01)
        await InkToolsFixture.settle()
        f.session.undo()
        #expect(page.drawing.strokes.count == 3, "one undo takes back one paste")
    }

    @Test func pasteOnAnotherPageKeepsThePositionAndCarriesElements() async throws {
        let f = try InkToolsFixture(pages: 2)
        let first = try pageWithTwoStrokes(f)
        let second = try f.page(1)
        let sticker = ElementValue(pageID: first.pageID, kind: .sticker, frame: CGRect(x: 300, y: 200, width: 60, height: 60), zIndex: 2)
        try first.elements.add(sticker, undoName: "Add")
        f.lasso.selectAll(page: first, editor: f.session)
        try await perform("ink.copy", f, first)

        try f.clipboard.paste(into: second, editor: f.session)
        #expect(second.drawing.strokes.count == 2)
        #expect(second.drawing.strokes[0].renderBounds == first.drawing.strokes[0].renderBounds)
        let element = try #require(second.elements.all.first)
        #expect(element.frame == sticker.frame && element.id != sticker.id && element.pageID == second.pageID)
        #expect(f.session.selection.pageID == second.pageID && f.session.selection.elementIDs == [element.id])
        #expect(first.elements.all.count == 1)
    }

    @Test func pastedShapesKeepTheirLookAndAreNotTheOriginals() async throws {
        let f = try InkToolsFixture()
        let page = try f.page()
        let shape = try f.addShape(.ellipse(center: CGPoint(x: 200, y: 200), radii: CGSize(width: 50, height: 30), rotation: 0), to: page, fill: "#FFE066")
        f.session.selection.select(pageID: page.pageID, strokeIDs: [], elementIDs: [shape.id], bounds: shape.frame)
        try await perform("ink.copy", f, page)
        try f.clipboard.paste(into: page, editor: f.session)
        let copy = try #require(page.elements.all.first { $0.id != shape.id })
        #expect(copy.payload == shape.payload && copy.zIndex > shape.zIndex)
        #expect(copy.frame.origin.x == shape.frame.origin.x + PastePlacement.nudge)
    }

    @Test func pasteTakesAnImageFromAnotherApp() throws {
        let f = try InkToolsFixture()
        let page = try f.page()
        let image = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 100)).image { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 200, height: 100))
        }
        f.pasteboard.image = image
        #expect(f.clipboard.canPaste)
        try f.clipboard.paste(into: page, editor: f.session)
        let element = try #require(page.elements.all.first)
        #expect(element.kind == .image && element.assetID != nil)
        #expect(PayloadCodec.decode(ImagePayload.self, from: element.payload)?.originalSize == CGSize(width: 200, height: 100))
        #expect(abs(page.pageSize.width / 2 - element.frame.midX) < 0.5)
        let stored = try #require(f.services.pages.page(id: page.pageID))
        #expect(stored.id == page.pageID)
    }

    @Test func pasteWithNothingOnThePasteboardSaysSo() throws {
        let f = try InkToolsFixture()
        let page = try f.page()
        f.pasteboard.items = []
        #expect(!f.clipboard.canPaste)
        #expect(throws: InkToolsError.self) { try f.clipboard.paste(into: page, editor: f.session) }
        f.pasteboard.string = "just text"
        #expect(throws: InkToolsError.self) { try f.clipboard.paste(into: page, editor: f.session) }
        #expect(page.drawing.strokes.isEmpty && page.elements.all.isEmpty)
    }

    @Test func damagedClipboardDataIsNotPasted() throws {
        let f = try InkToolsFixture()
        let page = try f.page()
        f.pasteboard.setData(Data("garbage".utf8), forPasteboardType: SelectionClipboard.pasteboardType)
        #expect(throws: InkToolsError.self) { try f.clipboard.paste(into: page, editor: f.session) }
    }

    @Test func cutCopiesBeforeItRemoves() async throws {
        let f = try InkToolsFixture()
        let page = try pageWithTwoStrokes(f)
        f.select([1], on: page)
        try await perform("ink.cut", f, page)
        #expect(page.drawing.strokes.count == 1 && f.session.selection.isEmpty)
        let data = try #require(f.pasteboard.data(forPasteboardType: SelectionClipboard.pasteboardType))
        let clip = try #require(SelectionClipboard.decode(data))
        #expect(try PKDrawing(data: clip.strokes).strokes.count == 1)
        try f.clipboard.paste(into: page, editor: f.session)
        #expect(page.drawing.strokes.count == 2, "the cut ink comes back with paste")
    }

    // MARK: Duplicate and delete

    @Test func duplicateSelectsTheCopy() async throws {
        let f = try InkToolsFixture()
        let page = try pageWithTwoStrokes(f)
        f.select([0], on: page)
        try await perform("ink.duplicate", f, page)
        #expect(page.drawing.strokes.count == 3 && Set(page.strokeIDs).count == 3)
        #expect(f.session.selection.strokeIDs == [page.strokeIDs[2]])
        #expect(f.session.selection.bounds?.minX ?? 0 > page.drawing.strokes[0].renderBounds.minX)
    }

    @Test func deleteRemovesTheSelectionAndUndoBringsItBack() async throws {
        let f = try InkToolsFixture()
        let page = try pageWithTwoStrokes(f)
        let shape = try f.addShape(.rectangle(center: CGPoint(x: 300, y: 500), size: CGSize(width: 80, height: 60), rotation: 0), to: page)
        f.lasso.selectAll(page: page, editor: f.session)
        await InkToolsFixture.settle()
        try await perform("ink.delete", f, page)
        #expect(page.drawing.strokes.isEmpty && page.elements.all.isEmpty)
        await InkToolsFixture.settle()
        f.session.undo()
        #expect(page.drawing.strokes.count == 2 && page.elements.all.map(\.id) == [shape.id])
    }

    // MARK: Style

    @Test func recolorChangesInkAndShapesInOneUndoStep() async throws {
        let f = try InkToolsFixture()
        let page = try pageWithTwoStrokes(f)
        let shape = try f.addShape(.rectangle(center: CGPoint(x: 300, y: 500), size: CGSize(width: 80, height: 60), rotation: 0), to: page)
        f.lasso.selectAll(page: page, editor: f.session)
        await InkToolsFixture.settle()

        try SelectionStyler(selection: f.session.selection, page: page, editor: f.session).recolor("#FF0000")
        #expect(page.drawing.strokes.allSatisfy { $0.ink.color.hexString == "#FF0000" })
        let payload = try f.shapePayload(shape.id, on: page)
        #expect(payload.strokeHex == "#FF0000")
        #expect(f.session.selection.strokeIDs == Set(page.strokeIDs), "the selection follows the re-identified strokes")

        await InkToolsFixture.settle()
        f.session.undo()
        #expect(page.drawing.strokes.allSatisfy { $0.ink.color.hexString == "#000000" })
        let back = try f.shapePayload(shape.id, on: page)
        #expect(back.strokeHex == "#112233")
    }

    @Test func widthAndFillApplyToShapes() async throws {
        let f = try InkToolsFixture()
        let page = try f.page()
        let shape = try f.addShape(.triangle([CGPoint(x: 200, y: 100), CGPoint(x: 260, y: 200), CGPoint(x: 140, y: 200)]), to: page, width: 2)
        f.session.selection.select(pageID: page.pageID, strokeIDs: [], elementIDs: [shape.id], bounds: shape.frame)
        let styler = SelectionStyler(selection: f.session.selection, page: page, editor: f.session)
        try styler.setWidth(9)
        await InkToolsFixture.settle()
        try styler.setFill("#00FF00")
        let payload = try f.shapePayload(on: page)
        #expect(payload.lineWidth == 9 && payload.fillHex == "#00FF00")
        await InkToolsFixture.settle()
        try styler.setFill(nil)
        #expect(try f.shapePayload(on: page).fillHex == nil)
    }

    @Test func styleActionOpensASheetOnlyForStyleableSelections() async throws {
        let f = try InkToolsFixture()
        let page = try pageWithTwoStrokes(f)
        let style = try f.action("ink.style")
        f.select([0], on: page)
        #expect(style.isEnabled(for: f.session.selection, editor: f.session))
        try await perform("ink.style", f, page)
        #expect(f.session.sheet != nil)
        let sticker = ElementValue(pageID: page.pageID, kind: .sticker, frame: CGRect(x: 10, y: 10, width: 40, height: 40), zIndex: 1)
        try page.elements.add(sticker, undoName: "Add")
        f.session.selection.select(pageID: page.pageID, strokeIDs: [], elementIDs: [sticker.id], bounds: sticker.frame)
        #expect(!style.isEnabled(for: f.session.selection, editor: f.session), "stickers have no colour or width to change")
    }

    @Test func actionsAreDisabledWithoutASelection() throws {
        let f = try InkToolsFixture()
        for action in InkSelectionActions.make(host: f.host, clipboard: f.clipboard) {
            #expect(!action.isEnabled(for: f.session.selection, editor: f.session), "\(action.id)")
        }
    }

    // MARK: Screenshot

    @Test func screenshotShowsOnlyTheSelectionAndOpensASheet() async throws {
        let f = try InkToolsFixture()
        let page = try pageWithTwoStrokes(f)
        f.select([0], on: page)
        let contents = try #require(SelectionContents(selection: f.session.selection, page: page))
        let image = try await SelectionImageRenderer(host: f.host).image(of: contents, scale: 2)
        let cg = try #require(image.cgImage)
        #expect(abs(image.size.width - (contents.bounds.width + 12)) < 1 && image.scale == 2)
        // The mid-point of the selected stroke is inked; the unselected stroke's area is not part of the image at all.
        let local = CGPoint(x: (150 - contents.bounds.minX + 6) * 2, y: (120 - contents.bounds.minY + 6) * 2)
        #expect(InkSketch.alpha(of: cg, x: Int(local.x), y: Int(local.y)) > 0)
        #expect(InkSketch.alpha(of: cg, x: 1, y: cg.height - 2) == 0, "transparent where nothing is drawn")

        try await perform("ink.screenshot", f, page)
        #expect(f.session.sheet != nil)
    }

    @Test func screenshotIncludesShapesFromTheirRenderer() async throws {
        let f = try InkToolsFixture()
        let page = try f.page()
        let shape = try f.addShape(.rectangle(center: CGPoint(x: 200, y: 200), size: CGSize(width: 100, height: 60), rotation: 0), to: page, fill: "#FF0000")
        f.session.selection.select(pageID: page.pageID, strokeIDs: [], elementIDs: [shape.id], bounds: shape.frame)
        let contents = try #require(SelectionContents(selection: f.session.selection, page: page))
        let image = try await SelectionImageRenderer(host: f.host).image(of: contents, scale: 1)
        let cg = try #require(image.cgImage)
        #expect(InkSketch.alpha(of: cg, x: cg.width / 2, y: cg.height / 2) == 255, "the fill is drawn")
    }

    @Test func imageFrameFitsAndCentresWithoutEnlarging() {
        let page = CGSize(width: 600, height: 800)
        let small = ClipboardService.imageFrame(for: CGSize(width: 100, height: 50), on: page)
        #expect(small.size == CGSize(width: 100, height: 50) && small.midX == 300 && small.midY == 400)
        let big = ClipboardService.imageFrame(for: CGSize(width: 3000, height: 1000), on: page)
        #expect(abs(big.width - 360) < 0.001 && big.minX > 0)
        #expect(ClipboardService.imageFrame(for: .zero, on: page).width > 0)
    }

    // MARK: Save as element

    @Test func saveAsElementOpensTheNamingSheet() async throws {
        let f = try InkToolsFixture()
        let page = try pageWithTwoStrokes(f)
        f.select([0], on: page)
        try await perform("ink.saveElement", f, page)
        #expect(f.session.sheet != nil)
        #expect(try f.services.elementLibrary.all().isEmpty, "nothing is saved until the user confirms a name")
        let contents = try #require(SelectionContents(selection: f.session.selection, page: page))
        let saved = try f.services.elementLibrary.save(name: "Wave", category: "My Elements", from: contents.snapshot, thumbnail: Data([1]))
        #expect(try f.services.elementLibrary.all().map(\.id) == [saved.id])
        let inserted = try f.services.elementLibrary.insert(saved, into: page, at: CGPoint(x: 300, y: 600), scale: 1)
        #expect(page.drawing.strokes.count == 3 && inserted.bounds.midY == 600)
    }
}
