import SwiftUI
import UIKit
import SheafnoteCore

/// Text boxes: live view below the ink, vector-friendly export through CoreText-backed attributed drawing.
@MainActor
final class TextElementRenderer: ElementRenderer {
    let kind = ElementKind.text
    let slot = PageLayerSlot.belowInk
    private let editing: TextEditSession

    init(editing: TextEditSession) { self.editing = editing }

    func makeView(for element: ElementValue, page: PageContext) -> AnyView {
        AnyView(TextElementView(element: element, session: editing))
    }

    func draw(_ element: ElementValue, into ctx: CGContext, assets: AssetResolver, options: RenderOptions) async throws {
        guard let payload = element.decoded(TextPayload.self) else { return }
        TextExportDrawing.draw(payload, frame: element.frame, rotation: element.rotation, in: ctx)
    }

    func hitTester(for element: ElementValue) -> any ElementHitTesting { OrientedBoxHitTester(element: element) }

    func beginEditing(_ element: ElementValue, page: PageContext, editor: EditorContext) {
        editing.begin(existing: element, on: page)
        editor.toolState.select(.text)
    }
}

/// Draws a text box into a top-left-origin context (page space).
enum TextExportDrawing {
    static func draw(_ payload: TextPayload, frame: CGRect, rotation: Double, in ctx: CGContext) {
        guard frame.width > 0, frame.height > 0 else { return }
        let element = ElementValue(pageID: UUID(), kind: .text, frame: frame, rotation: rotation)
        ElementDrawing.withRotation(element, in: ctx) {
            ctx.clip(to: frame)
            if let background = TextStyling.backgroundColor(for: payload) {
                ctx.setFillColor(background.cgColor)
                ctx.addPath(CGPath(roundedRect: frame, cornerWidth: 3, cornerHeight: 3, transform: nil))
                ctx.fillPath()
            }
            let inner = frame.insetBy(dx: TextBoxLayout.padding, dy: TextBoxLayout.padding)
            UIGraphicsPushContext(ctx)
            TextStyling.attributed(payload).draw(with: inner, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
            UIGraphicsPopContext()
        }
    }
}
