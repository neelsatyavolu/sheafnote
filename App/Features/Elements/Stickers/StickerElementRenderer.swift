import SwiftUI
import SheafnoteCore

/// Vector sticker drawn with the shared Core renderer, so it is identical on screen, in thumbnails and in exports.
struct StickerArtView: View {
    let sticker: StickerDefinition
    let tintHex: String?

    var body: some View {
        Canvas { context, size in
            context.withCGContext { cg in
                StickerRenderer.draw(sticker, tintHex: tintHex, in: cg, rect: CGRect(origin: .zero, size: size))
            }
        }
    }
}

/// A sticker element. A sticker id this version does not know (for example one added by a newer app version) shows
/// a neutral placeholder and keeps its data.
struct StickerElementView: View {
    let element: ElementValue

    var body: some View {
        if let payload = element.decoded(StickerPayload.self), let sticker = StickerCatalog.sticker(id: payload.stickerID) {
            StickerArtView(sticker: sticker, tintHex: payload.tintHex)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(String(localized: String.LocalizationValue(sticker.name), table: "Elements")))
                .accessibilityHint(Text("Sticker", tableName: "Elements"))
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(.quaternary)
                Image(systemName: "questionmark").foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Unknown sticker", tableName: "Elements"))
        }
    }
}

@MainActor
final class StickerElementRenderer: ElementRenderer {
    let kind = ElementKind.sticker
    let slot = PageLayerSlot.belowInk

    func makeView(for element: ElementValue, page: PageContext) -> AnyView { AnyView(StickerElementView(element: element)) }

    func draw(_ element: ElementValue, into ctx: CGContext, assets: AssetResolver, options: RenderOptions) async throws {
        guard let payload = element.decoded(StickerPayload.self),
              let sticker = StickerCatalog.sticker(id: payload.stickerID) else { return }
        ElementDrawing.withRotation(element, in: ctx) {
            StickerRenderer.draw(sticker, tintHex: payload.tintHex, in: ctx, rect: element.frame)
        }
    }

    func hitTester(for element: ElementValue) -> any ElementHitTesting { OrientedBoxHitTester(element: element) }

    /// Stickers have no editor of their own; their tint is changed from the element tool's options row.
    func beginEditing(_ element: ElementValue, page: PageContext, editor: EditorContext) {}
}
