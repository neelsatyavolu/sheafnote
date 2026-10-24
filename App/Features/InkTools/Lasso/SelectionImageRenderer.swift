import PencilKit
import UIKit
import SheafnoteCore

/// Draws just the selected strokes and elements (not whatever else lies in the same area) into an image.
@MainActor
struct SelectionImageRenderer {
    let host: FeatureHost

    /// `background` nil gives a transparent image.
    func image(of contents: SelectionContents, scale: CGFloat, background: UIColor? = nil, padding: CGFloat = 6) async throws -> UIImage {
        let area = contents.bounds.insetBy(dx: -padding, dy: -padding)
        let width = max(1, Int((area.width * scale).rounded())), height = max(1, Int((area.height * scale).rounded()))
        guard width <= 8_192, height <= 8_192, let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw InkToolsError.imageFailed }
        if let background {
            ctx.setFillColor(background.cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: scale, y: -scale)
        ctx.translateBy(x: -area.minX, y: -area.minY)

        try await draw(contents.elements, slot: .belowInk, into: ctx)
        drawInk(contents, area: area, scale: scale, into: ctx)
        try await draw(contents.elements, slot: .aboveInk, into: ctx)
        guard let cgImage = ctx.makeImage() else { throw InkToolsError.imageFailed }
        return UIImage(cgImage: cgImage, scale: scale, orientation: .up)
    }

    /// Black ink on white at a size Vision reads well, for handwriting recognition.
    func handwritingImage(of contents: SelectionContents) async throws -> CGImage {
        let scale = min(3, 2_400 / max(contents.bounds.width, contents.bounds.height, 1))
        let inkOnly = SelectionContents.blackInk(contents)
        let image = try await self.image(of: inkOnly, scale: max(scale, 1), background: .white, padding: 16)
        guard let cg = image.cgImage else { throw InkToolsError.imageFailed }
        return cg
    }

    private func drawInk(_ contents: SelectionContents, area: CGRect, scale: CGFloat, into ctx: CGContext) {
        guard !contents.strokes.isEmpty else { return }
        var image: UIImage?
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            image = contents.drawing.image(from: area, scale: scale)
        }
        guard let image else { return }
        UIGraphicsPushContext(ctx)
        image.draw(in: area)
        UIGraphicsPopContext()
    }

    private func draw(_ elements: [ElementValue], slot: PageLayerSlot, into ctx: CGContext) async throws {
        for element in elements {
            guard let renderer = host.elementRenderers.renderer(for: element.kind), renderer.slot == slot else { continue }
            ctx.saveGState()
            defer { ctx.restoreGState() }
            try await renderer.draw(element, into: ctx, assets: host.services.pages, options: .screen)
        }
    }
}

extension SelectionContents {
    /// The same strokes in black and without elements, so white or pale ink is still read as writing.
    static func blackInk(_ contents: SelectionContents) -> SelectionContents {
        contents.replacing(strokes: contents.strokes.map { item in
            let ink = PKInk(item.stroke.ink.inkType, color: .black)
            let stroke = PKStroke(ink: ink, path: item.stroke.path, transform: item.stroke.transform, mask: item.stroke.mask)
            return IdentifiedStroke(id: item.id, stroke: stroke)
        }, elements: [])
    }
}
