import PencilKit
import SwiftUI
import Testing
import UIKit
import SheafnoteCore
@testable import Sheafnote

@MainActor
@Suite struct ImagesAndLibraryTests {
    // MARK: Import

    @Test func importerKeepsTransparencyAsPNG() throws {
        let prepared = try ImageImporter.prepare(ElementsFixture.pngData(width: 120, height: 80, transparent: true))
        #expect(prepared.hasAlpha && prepared.uti == "public.png")
        #expect(prepared.pixelSize == CGSize(width: 120, height: 80))
    }

    @Test func importerStoresOpaqueImagesAsJPEG() throws {
        let prepared = try ImageImporter.prepare(ElementsFixture.pngData(width: 120, height: 80, transparent: false))
        #expect(!prepared.hasAlpha && prepared.uti == "public.jpeg")
    }

    @Test func importerScalesDownHugeImages() throws {
        let prepared = try ImageImporter.prepare(ElementsFixture.pngData(width: 6000, height: 3000, transparent: false))
        #expect(prepared.pixelSize == CGSize(width: 4096, height: 2048))
        #expect(ImageImporter.decode(prepared.data)?.width == 4096)
    }

    @Test func importerNeverUpscales() throws {
        #expect(try ImageImporter.prepare(ElementsFixture.pngData(width: 40, height: 20, transparent: false)).pixelSize == CGSize(width: 40, height: 20))
        #expect(ImageImporter.decode(ElementsFixture.pngData(width: 40, height: 20), maxPixel: 2400)?.width == 40)
    }

    @Test func importerRejectsGarbageWithAFriendlyError() {
        #expect(throws: ImageImportError.self) { try ImageImporter.prepare(Data("not an image".utf8)) }
        #expect(ImageImportError.unreadable.errorDescription?.isEmpty == false)
        #expect(ImageImportError.encodeFailed.errorDescription?.isEmpty == false)
    }

    @Test func importerAppliesExifOrientation() throws {
        // A 200x100 landscape JPEG tagged "rotated 90 degrees" must come out portrait.
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 100), format: format).image { ctx in
            UIColor.blue.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 200, height: 100))
        }
        let rotated = UIImage(cgImage: try #require(image.cgImage), scale: 1, orientation: .right)
        let data = try #require(rotated.jpegData(compressionQuality: 1))
        #expect(try ImageImporter.prepare(data).pixelSize == CGSize(width: 100, height: 200))
    }

    // MARK: Insertion

    @Test func insertingAnImageStoresTheAssetOnceAndSelectsTheElement() throws {
        let f = try ElementsFixture()
        let page = try f.page()
        let data = ElementsFixture.pngData(width: 800, height: 400, transparent: false)
        let first = try f.inserter.insertImage(data: data, filename: "wide.png")
        let second = try f.inserter.insertImage(data: data, filename: "wide.png")
        #expect(first.kind == .image && first.assetID != nil)
        #expect(first.assetID == second.assetID)                       // same bytes, one stored asset
        #expect(second.zIndex > first.zIndex)
        let payload = try #require(first.decoded(ImagePayload.self))
        #expect(payload.originalSize == CGSize(width: 800, height: 400) && payload.cropRect == CGRect(x: 0, y: 0, width: 1, height: 1))
        #expect(abs(first.frame.width / first.frame.height - 2) < 0.01)
        #expect(CGRect(origin: .zero, size: page.pageSize).contains(first.frame))
        #expect(f.session.selection.elementIDs == [second.id])
        #expect(page.elementValues.count == 2)
    }

    @Test func insertImageUndoRemovesTheElementOnly() async throws {
        let f = try ElementsFixture()
        let page = try f.page()
        await EditorFixture.settle()
        let element = try f.inserter.insertImage(data: ElementsFixture.pngData(), filename: nil)
        await EditorFixture.settle()
        f.session.undo()
        #expect(page.elementValues.isEmpty)
        // The stored asset is kept: undo never deletes user data.
        #expect(try await f.services.pages.data(for: try #require(element.assetID)).isEmpty == false)
    }

    @Test func badImageDataThrowsAndAddsNothing() throws {
        let f = try ElementsFixture()
        let page = try f.page()
        #expect(throws: ImageImportError.self) { try f.inserter.insertImage(data: Data([1, 2, 3]), filename: nil) }
        #expect(page.elementValues.isEmpty)
    }

    @Test func insertingWithoutAPageIsAnErrorNotACrash() throws {
        let f = try ElementsFixture()
        let stub = NoPageEditor(base: f.session)
        let inserter = ElementInserter(editor: stub, host: f.host)
        #expect(throws: ElementInsertError.self) { try inserter.insertSticker(StickerCatalog.all[0]) }
        #expect(ElementInsertError.noPage.errorDescription?.isEmpty == false)
        #expect(ElementInsertError.photoUnavailable.errorDescription?.isEmpty == false)
    }

    @Test func stickersAreInsertedCenteredWithSensibleSizes() throws {
        let f = try ElementsFixture()
        let page = try f.page()
        for sticker in StickerCatalog.all {
            let e = try f.inserter.insertSticker(sticker)
            #expect(abs(e.frame.midX - page.pageSize.width / 2) < 0.5 && abs(e.frame.midY - page.pageSize.height / 2) < 0.5)
            #expect(abs(e.frame.width / e.frame.height - sticker.aspectRatio) < 0.01)
            #expect(CGRect(origin: .zero, size: page.pageSize).contains(e.frame))
        }
        #expect(page.elementValues.count == StickerCatalog.all.count)
    }

    // MARK: Saved elements

    @Test func savingASelectionAndInsertingItAgainRoundTrips() async throws {
        let f = try ElementsFixture()
        let page = try f.page()
        let sticker = try f.inserter.insertSticker(try #require(StickerCatalog.sticker(id: "star")))
        let selection = f.session.selection
        let action = SaveAsElementAction()
        #expect(action.isEnabled(for: selection, editor: f.session))
        let snapshot = action.makeSnapshot(selection: selection, page: page, bounds: try #require(selection.bounds))
        #expect(snapshot.elements.map(\.id) == [sticker.id])
        let thumbnail = try #require(UIImage(cgImage: try await f.services.pageRenderer.renderImage(
            pageID: page.pageID, rect: snapshot.bounds, scale: 1,
            options: RenderOptions(includeBackground: false, includeInk: true, includeElements: true, forExport: false, hideTape: false))).pngData())
        let saved = try f.services.elementLibrary.save(name: "My star", category: "Marks", from: snapshot, thumbnail: thumbnail)
        #expect(try f.services.elementLibrary.all().map(\.name) == ["My star"])

        try f.inserter.insertSaved(saved)
        #expect(page.elementValues.count == 2)
        let copy = try #require(page.elementValues.first { $0.id != sticker.id })
        #expect(copy.kind == .sticker && copy.payload == sticker.payload)
        #expect(f.session.selection.elementIDs == [copy.id])
    }

    @Test func savedElementsCanBeRenamedAndDeleted() throws {
        let f = try ElementsFixture()
        let page = try f.page()
        _ = try f.inserter.insertSticker(try #require(StickerCatalog.sticker(id: "bolt")))
        let selection = f.session.selection
        let snapshot = SaveAsElementAction().makeSnapshot(selection: selection, page: page, bounds: try #require(selection.bounds))
        let saved = try f.services.elementLibrary.save(name: "Bolt", category: "My Elements", from: snapshot, thumbnail: Data())
        try f.services.elementLibrary.rename(id: saved.id, to: "Zap")
        #expect(try f.services.elementLibrary.all().first?.name == "Zap")
        try f.services.elementLibrary.delete(id: saved.id)
        #expect(try f.services.elementLibrary.all().isEmpty)
    }

    @Test func savedInkOnlyElementIsInsertedWithoutASelection() throws {
        let f = try ElementsFixture()
        let page = try f.page()
        page.setDrawing(PKDrawing(strokes: [TestInk.stroke(from: CGPoint(x: 20, y: 20), to: CGPoint(x: 120, y: 80))]), undoName: "Draw")
        let ids = Set(page.strokeIDs)
        let bounds = page.drawing.bounds
        f.session.selection.select(pageID: page.pageID, strokeIDs: ids, elementIDs: [], bounds: bounds)
        let snapshot = SaveAsElementAction().makeSnapshot(selection: f.session.selection, page: page, bounds: bounds)
        #expect(snapshot.elements.isEmpty && !snapshot.strokes.isEmpty)
        let saved = try f.services.elementLibrary.save(name: "Squiggle", category: "Ink", from: snapshot, thumbnail: Data())
        f.session.selection.clear()
        try f.inserter.insertSaved(saved)
        #expect(page.drawing.strokes.count == 2)
        #expect(f.session.selection.isEmpty)
    }

    @Test func selectionActionsEnableForTheRightSelections() throws {
        let f = try ElementsFixture()
        let page = try f.page()
        let editText = EditTextAction(host: f.host), crop = CropImageAction(host: f.host), save = SaveAsElementAction()
        let selection = f.session.selection
        #expect(!save.isEnabled(for: selection, editor: f.session) && !editText.isEnabled(for: selection, editor: f.session))
        let image = try f.inserter.insertImage(data: ElementsFixture.pngData(), filename: nil)
        #expect(crop.isEnabled(for: selection, editor: f.session) && !editText.isEnabled(for: selection, editor: f.session))
        let text = try page.elements.add(ElementValue(pageID: page.pageID, kind: .text, frame: CGRect(x: 0, y: 0, width: 100, height: 30),
                                                      payload: PayloadCodec.encode(TextPayload(text: "t"))), undoName: "Add")
        ElementSelecting.select(text, on: page, editor: f.session, host: f.host)
        #expect(editText.isEnabled(for: selection, editor: f.session) && !crop.isEnabled(for: selection, editor: f.session))
        selection.select(pageID: page.pageID, strokeIDs: [], elementIDs: [image.id, text.id], bounds: CGRect(x: 0, y: 0, width: 100, height: 100))
        #expect(save.isEnabled(for: selection, editor: f.session) && !editText.isEnabled(for: selection, editor: f.session))
    }

    // MARK: Page rendering

    @Test func pageRendererShowsElementsAndHonorsRenderOptions() async throws {
        let f = try ElementsFixture()
        let page = try f.page()
        let sticker = try f.inserter.insertSticker(try #require(StickerCatalog.sticker(id: "circle")))
        let rect = sticker.frame
        let withElements = try await f.services.pageRenderer.renderImage(pageID: page.pageID, rect: nil, scale: 1, options: .screen)
        var none = RenderOptions.screen
        none.includeElements = false
        let without = try await f.services.pageRenderer.renderImage(pageID: page.pageID, rect: nil, scale: 1, options: none)
        func pixel(_ image: CGImage) -> [UInt8] {
            let x = Int(rect.midX), y = Int(rect.midY)
            let data = CFDataGetBytePtr(image.dataProvider!.data!)!
            let i = y * image.bytesPerRow + x * 4
            return [data[i], data[i + 1], data[i + 2]]
        }
        #expect(pixel(withElements) != pixel(without))
        #expect(pixel(without) == [255, 255, 255])
    }
}

/// An editor with no open page, to check the "no page" error path.
@MainActor
private final class NoPageEditor: EditorContext {
    let base: NotebookSession
    init(base: NotebookSession) { self.base = base }
    var notebook: Notebook { base.notebook }
    var services: AppServices { base.services }
    var toolState: ToolState { base.toolState }
    var presets: any ToolPresetStore { base.presets }
    var selection: SelectionModel { base.selection }
    var selectionTransformer: any SelectionTransforming { base.selectionTransformer }
    var currentPage: (any PageContext)? { nil }
    var visiblePages: [any PageContext] { [] }
    var undoManager: UndoManager { base.undoManager }
    func goToPage(id: UUID, animated: Bool) {}
    func present(_ sheet: EditorSheet) {}
    func showToast(_ message: LocalizedStringResource) {}
    func setZoomScale(_ scale: CGFloat, animated: Bool) {}
}
