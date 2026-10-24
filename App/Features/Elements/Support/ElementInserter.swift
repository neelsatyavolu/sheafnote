import CoreGraphics
import Foundation
import PencilKit
import SheafnoteCore

enum ElementInsertError: LocalizedError {
    case noPage
    case photoUnavailable

    var errorDescription: String? {
        switch self {
        case .noPage: String(localized: "Open a page first, then try again.", table: "Elements")
        case .photoUnavailable: String(localized: "The photo could not be loaded. Check that it is available on this device and try again.",
                                       table: "Elements")
        }
    }
}

/// Puts images, stickers and saved elements on the current page and selects what was added.
@MainActor
struct ElementInserter {
    let editor: EditorContext
    unowned let host: FeatureHost

    /// Points per image pixel at natural size (most pictures are 2x).
    private static let pointsPerPixel: CGFloat = 0.5

    var page: (any PageContext)? { editor.currentPage }

    private func requirePage() throws -> any PageContext {
        guard let page else { throw ElementInsertError.noPage }
        return page
    }

    private var services: AppServices { editor.services }

    // MARK: Images

    @discardableResult
    func insertImage(data: Data, filename: String?) throws -> ElementValue {
        let page = try requirePage()
        let prepared = try ImageImporter.prepare(data)
        let asset = try services.pages.importAsset(data: prepared.data, kind: .image, filename: filename, uti: prepared.uti)
        let natural = CGSize(width: prepared.pixelSize.width * Self.pointsPerPixel, height: prepared.pixelSize.height * Self.pointsPerPixel)
        let frame = ImageCropMath.insertionFrame(imageSize: natural, pageSize: page.pageSize,
                                                 center: CGPoint(x: page.pageSize.width / 2, y: page.pageSize.height / 2))
        let element = ElementValue(pageID: page.pageID, kind: .image, frame: frame, zIndex: TextBoxLayout.nextZIndex(in: page.elements.all),
                                   payload: PayloadCodec.encode(ImagePayload(originalSize: prepared.pixelSize)), assetID: asset.id)
        return try add(element, name: LocalizedStringResource("Insert Image", table: "Elements"), on: page)
    }

    // MARK: Stickers

    @discardableResult
    func insertSticker(_ sticker: StickerDefinition) throws -> ElementValue {
        let page = try requirePage()
        let longest: CGFloat = sticker.category == .washi ? 220 : 120
        let scale = longest / max(sticker.size.width, sticker.size.height)
        let size = CGSize(width: sticker.size.width * scale, height: sticker.size.height * scale)
        let center = CGPoint(x: page.pageSize.width / 2, y: page.pageSize.height / 2)
        let frame = CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
        let element = ElementValue(pageID: page.pageID, kind: .sticker, frame: frame, zIndex: TextBoxLayout.nextZIndex(in: page.elements.all),
                                   payload: PayloadCodec.encode(StickerPayload(stickerID: sticker.id)))
        return try add(element, name: LocalizedStringResource("Insert Sticker", table: "Elements"), on: page)
    }

    // MARK: Saved elements

    func insertSaved(_ saved: SavedElementValue) throws {
        let page = try requirePage()
        let center = CGPoint(x: page.pageSize.width / 2, y: page.pageSize.height / 2)
        let snapshot = try services.elementLibrary.insert(saved, into: page, at: center, scale: 1)
        // Only a lone element can be selected through the element selection helper; anything with ink is left to the lasso.
        if let first = snapshot.elements.first, snapshot.elements.count == 1, !hasStrokes(snapshot.strokes) {
            ElementSelecting.select(first, on: page, editor: editor, host: host)
        } else {
            editor.selection.clear()
        }
    }

    private func hasStrokes(_ data: Data) -> Bool { (try? PKDrawing(data: data))?.strokes.isEmpty == false }

    // MARK: Z-order

    func moveToFront(_ element: ElementValue) throws { try reorder(element, toFront: true) }

    func moveToBack(_ element: ElementValue) throws { try reorder(element, toFront: false) }

    private func reorder(_ element: ElementValue, toFront: Bool) throws {
        let page = try requirePage()
        let others = page.elements.all.filter { $0.id != element.id }.map(\.zIndex)
        let z = toFront ? (others.max() ?? -1) + 1 : (others.min() ?? 1) - 1
        let name = toFront ? LocalizedStringResource("Bring to Front", table: "Elements")
                           : LocalizedStringResource("Send to Back", table: "Elements")
        try page.elements.update(id: element.id, undoName: name) {
            $0.zIndex = z
        }
    }

    // MARK: Helpers

    private func add(_ element: ElementValue, name: LocalizedStringResource, on page: any PageContext) throws -> ElementValue {
        let stored = try page.elements.add(element, undoName: name)
        ElementSelecting.select(stored, on: page, editor: editor, host: host)
        return stored
    }
}
