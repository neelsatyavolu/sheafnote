import SwiftUI
import UIKit
import SheafnoteCore

/// Images below the ink. The stored asset is never modified: the crop is a rectangle in the payload.
@MainActor
final class ImageElementRenderer: ElementRenderer {
    let kind = ElementKind.image
    let slot = PageLayerSlot.belowInk
    let cache: ElementImageCache
    private unowned let host: FeatureHost

    init(cache: ElementImageCache, host: FeatureHost) {
        self.cache = cache
        self.host = host
    }

    func makeView(for element: ElementValue, page: PageContext) -> AnyView {
        AnyView(ImageElementView(element: element, cache: cache))
    }

    func draw(_ element: ElementValue, into ctx: CGContext, assets: AssetResolver, options: RenderOptions) async throws {
        guard let assetID = element.assetID, let payload = element.decoded(ImagePayload.self) else { return }
        let data = try await assets.data(for: assetID)
        guard let full = ImageImporter.decode(data, maxPixel: options.forExport ? nil : ElementImageCache.screenMaxPixel) else {
            throw ImageImportError.unreadable
        }
        let pixels = ImageCropMath.pixelRect(for: payload.cropRect,
                                             originalSize: CGSize(width: full.width, height: full.height)).integral
        guard let cropped = full.cropping(to: pixels) else { return }
        ElementDrawing.withRotation(element, in: ctx) { ElementDrawing.draw(cropped, in: element.frame, ctx: ctx) }
    }

    func hitTester(for element: ElementValue) -> any ElementHitTesting { OrientedBoxHitTester(element: element) }

    /// Double-tap on an image opens the crop editor.
    func beginEditing(_ element: ElementValue, page: PageContext, editor: EditorContext) {
        ImageCropPresenter.present(element, page: page, editor: editor, cache: cache, host: host)
    }
}

/// The live image: the whole picture is laid out so that only the crop rectangle shows inside the element's frame.
struct ImageElementView: View {
    let element: ElementValue
    let cache: ElementImageCache
    @State private var image: UIImage?

    var body: some View {
        GeometryReader { geo in
            if let image, let payload = element.decoded(ImagePayload.self) {
                let crop = ImageCropMath.clamped(payload.cropRect)
                let full = CGSize(width: geo.size.width / crop.width, height: geo.size.height / crop.height)
                Image(uiImage: image)
                    .resizable()
                    .frame(width: full.width, height: full.height)
                    .offset(x: -crop.minX * full.width, y: -crop.minY * full.height)
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
                    .clipped()
            } else {
                ZStack {
                    Rectangle().fill(.quaternary)
                    Image(systemName: "photo").foregroundStyle(.secondary)
                }
            }
        }
        .task(id: element.assetID) {
            guard let id = element.assetID else { return }
            image = cache.cachedImage(for: id)
            if image == nil { image = await cache.image(for: id) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Image", tableName: "Elements"))
        .accessibilityAddTraits(.isImage)
        .accessibilityIdentifier("elements.image")
    }
}
