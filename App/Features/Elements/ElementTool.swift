import SwiftUI
import SheafnoteCore

/// The element/image tool: insert pictures, stickers and saved elements, and tap any element to select it. The editor's
/// selection overlay then provides move, resize and rotate.
@MainActor
final class ElementTool: EditorTool {
    let id = ToolID.element
    let title = LocalizedStringResource("Elements", table: "Elements")
    let symbolName = "photo.on.rectangle.angled"
    let placement = ToolPlacement.primary(order: 60)
    let supportedKinds: Set<NotebookKind> = [.paged, .whiteboard]
    let inputPolicy = ToolInputPolicy.overlayCapturesAll

    private unowned let host: FeatureHost
    private let imageCache: ElementImageCache

    init(host: FeatureHost, imageCache: ElementImageCache) {
        self.host = host
        self.imageCache = imageCache
    }

    func activate(in editor: EditorContext) {}

    func deactivate(in editor: EditorContext) {}

    func makeOptionsView(in editor: EditorContext) -> AnyView {
        AnyView(ElementOptionsRow(editor: editor, host: host, imageCache: imageCache))
    }

    func makeOverlay(for page: PageContext, in editor: EditorContext) -> AnyView? {
        AnyView(ElementToolOverlay(page: page, editor: editor, host: host))
    }
}

struct ElementToolOverlay: View {
    let page: any PageContext
    let editor: EditorContext
    let host: FeatureHost

    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(SpatialTapGesture().onEnded { select(at: $0.location) })
            .frame(width: page.pageSize.width, height: page.pageSize.height, alignment: .topLeading)
            .accessibilityHidden(true)
    }

    private func select(at point: CGPoint) {
        if let element = ElementSelecting.topElement(at: point, on: page, host: host) {
            ElementSelecting.select(element, on: page, editor: editor, host: host)
        } else {
            editor.selection.clear()
        }
    }
}
