import Foundation

/// Text boxes, images, stickers, saved elements and study tape: registers the element renderers, the text, element
/// and tape tools, and the selection actions "Save as Element", "Edit Text" and "Crop Image".
enum ElementsFeature: FeatureModule {
    static let id = "elements"

    static func register(into host: FeatureHost) {
        let textEditing = TextEditSession()
        let imageCache = ElementImageCache(pages: host.services.pages)

        host.elementRenderers.register(TextElementRenderer(editing: textEditing))
        host.elementRenderers.register(ImageElementRenderer(cache: imageCache, host: host))
        host.elementRenderers.register(StickerElementRenderer())
        host.elementRenderers.register(TapeElementRenderer())

        host.tools.register(ElementTool(host: host, imageCache: imageCache))
        host.tools.register(TextTool(editing: textEditing, host: host))
        host.tools.register(TapeTool(host: host))

        host.selectionActions.register(EditTextAction(host: host))
        host.selectionActions.register(CropImageAction(host: host))
        host.selectionActions.register(SaveAsElementAction())
    }
}
