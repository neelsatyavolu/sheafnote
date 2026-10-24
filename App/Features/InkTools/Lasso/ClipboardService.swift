import PencilKit
import UIKit
import UniformTypeIdentifiers
import SheafnoteCore

/// Copy and paste of selections through the system pasteboard. Sheafnote's own type carries ink and elements
/// losslessly (and travels to your other devices with Universal Clipboard); a PNG rides along for other apps, and
/// a plain image on the pasteboard pastes in as an image element.
@MainActor
final class ClipboardService {
    private let host: FeatureHost
    private let pasteboard: UIPasteboard
    private var lastChangeCount = -1
    private var pastesOfCurrent = 0

    init(host: FeatureHost, pasteboard: UIPasteboard = .general) {
        self.host = host
        self.pasteboard = pasteboard
    }

    var canPaste: Bool {
        pasteboard.contains(pasteboardTypes: [SelectionClipboard.pasteboardType]) || pasteboard.hasImages
    }

    // MARK: Copy

    func copy(_ contents: SelectionContents, page: any PageContext) async {
        let clip = SelectionClipboard(strokes: contents.strokes.isEmpty ? Data() : contents.drawing.dataRepresentation(),
                                      elements: contents.elements, bounds: contents.bounds, sourcePageID: contents.pageID)
        var item: [String: Any] = [SelectionClipboard.pasteboardType: clip.encoded()]
        // The picture is a courtesy for other apps; if it cannot be made the copy still works inside Sheafnote.
        if let image = try? await SelectionImageRenderer(host: host).image(of: contents, scale: 2), let png = image.pngData() {
            item[UTType.png.identifier] = png
        }
        pasteboard.setItems([item], options: [:])
        lastChangeCount = pasteboard.changeCount
        pastesOfCurrent = 0
    }

    // MARK: Paste

    /// Pastes onto `page` and selects what arrived. Throws `nothingToPaste` when the pasteboard holds neither.
    func paste(into page: any PageContext, editor: EditorContext) throws {
        let services = editor.services
        let manager = editor.undoManager
        manager.beginUndoGrouping()
        defer { manager.endUndoGrouping() }
        if let data = pasteboard.data(forPasteboardType: SelectionClipboard.pasteboardType), let clip = SelectionClipboard.decode(data) {
            try pasteSelection(clip, into: page, editor: editor)
        } else if pasteboard.hasImages, let image = pasteboard.image {
            try pasteImage(image, into: page, services: services, editor: editor)
        } else {
            throw InkToolsError.nothingToPaste
        }
    }

    private func pasteSelection(_ clip: SelectionClipboard, into page: any PageContext, editor: EditorContext) throws {
        if pasteboard.changeCount != lastChangeCount {
            lastChangeCount = pasteboard.changeCount
            pastesOfCurrent = 0
        }
        let offset = PastePlacement.offset(for: clip.bounds, sourcePageID: clip.sourcePageID, targetPageID: page.pageID,
                                           targetSize: page.pageSize, earlierPastes: pastesOfCurrent)
        let move = CGAffineTransform(translationX: offset.width, y: offset.height)

        var strokeIDs: Set<StrokeID> = []
        if !clip.strokes.isEmpty {
            let drawing = try PKDrawing(data: clip.strokes).transformed(using: move)
            page.ink.edit(LocalizedStringResource("Paste", table: "InkTools")) { $0.append(contentsOf: drawing.strokes) }
            strokeIDs = Set(drawing.strokeIDs)
        }
        let top = page.elements.all.map(\.zIndex).max() ?? 0
        var elementIDs: Set<UUID> = []
        for copy in clip.elementCopies(for: page.pageID, offset: offset, topZIndex: top) {
            let stored = try page.elements.add(copy, undoName: LocalizedStringResource("Paste", table: "InkTools"))
            elementIDs.insert(stored.id)
        }
        pastesOfCurrent += 1
        editor.selection.select(pageID: page.pageID, strokeIDs: strokeIDs, elementIDs: elementIDs, bounds: clip.bounds.applying(move))
    }

    private func pasteImage(_ image: UIImage, into page: any PageContext, services: AppServices, editor: EditorContext) throws {
        guard let png = image.pngData() else { throw InkToolsError.imageFailed }
        let asset = try services.pages.importAsset(data: png, kind: .image, filename: nil, uti: UTType.png.identifier)
        let frame = Self.imageFrame(for: image.size, on: page.pageSize)
        let top = page.elements.all.map(\.zIndex).max() ?? 0
        let payload = ImagePayload(originalSize: image.size)
        let element = ElementValue(pageID: page.pageID, kind: .image, frame: frame, zIndex: top + 1,
                                   payload: PayloadCodec.encode(payload), assetID: asset.id)
        let stored = try page.elements.add(element, undoName: LocalizedStringResource("Paste", table: "InkTools"))
        editor.selection.select(pageID: page.pageID, strokeIDs: [], elementIDs: [stored.id], bounds: frame)
    }

    /// Centred on the page, at most 60 percent of its width and height, never enlarged.
    static func imageFrame(for size: CGSize, on page: CGSize) -> CGRect {
        guard size.width > 0, size.height > 0 else { return CGRect(x: 0, y: 0, width: 100, height: 100) }
        let scale = min(1, page.width * 0.6 / size.width, page.height * 0.6 / size.height)
        let fitted = CGSize(width: size.width * scale, height: size.height * scale)
        return CGRect(x: (page.width - fitted.width) / 2, y: (page.height - fitted.height) / 2, width: fitted.width, height: fitted.height)
    }
}
