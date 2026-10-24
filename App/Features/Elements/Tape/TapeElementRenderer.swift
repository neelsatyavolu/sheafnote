import SwiftUI
import SheafnoteCore

/// Study tape, drawn above the ink. Tapping it flips between covering and revealed.
@MainActor
final class TapeElementRenderer: ElementRenderer {
    let kind = ElementKind.tape
    let slot = PageLayerSlot.aboveInk

    func makeView(for element: ElementValue, page: PageContext) -> AnyView {
        AnyView(TapeElementView(element: element, page: page))
    }

    /// `RenderOptions.hideTape` forces every tape to cover (for a "hidden" export); otherwise each tape keeps its state.
    func draw(_ element: ElementValue, into ctx: CGContext, assets: AssetResolver, options: RenderOptions) async throws {
        guard let payload = element.decoded(TapePayload.self) else { return }
        ElementDrawing.withRotation(element, in: ctx) {
            ctx.translateBy(x: element.frame.minX, y: element.frame.minY)
            TapeRenderer.draw(payload, covering: StudyTape.isCovering(payload, forceHide: options.hideTape), in: ctx, size: element.frame.size)
        }
    }

    func hitTester(for element: ElementValue) -> any ElementHitTesting { OrientedBoxHitTester(element: element) }

    /// Double-tap behaves like a tap: flip the tape.
    func beginEditing(_ element: ElementValue, page: PageContext, editor: EditorContext) {
        TapeToggling.toggle(element, on: page, editor: editor)
    }
}

@MainActor
enum TapeToggling {
    static func toggle(_ element: ElementValue, on page: any PageContext, editor: EditorContext?) {
        // Read the live state so a quick double tap flips twice instead of setting the same state twice.
        let current = page.elements.all.first { $0.id == element.id } ?? element
        guard let payload = current.decoded(TapePayload.self) else { return }
        let toggled = StudyTape.toggled(payload)
        let name = toggled.isRevealed ? LocalizedStringResource("Reveal Tape", table: "Elements")
                                      : LocalizedStringResource("Cover with Tape", table: "Elements")
        do {
            try page.elements.update(id: element.id, undoName: name) { $0.payload = PayloadCodec.encode(toggled) }
        } catch {
            if let editor { ElementErrors.report(error, editor: editor) } else { ElementErrors.report(error, page: page) }
        }
    }
}

struct TapeElementView: View {
    let element: ElementValue
    let page: any PageContext

    var body: some View {
        let payload = element.decoded(TapePayload.self)
        let covering = payload.map { !$0.isRevealed } ?? true
        Canvas { context, size in
            guard let payload else { return }
            context.withCGContext { cg in TapeRenderer.draw(payload, covering: covering, in: cg, size: size) }
        }
        .contentShape(Rectangle())
        .onTapGesture { TapeToggling.toggle(element, on: page, editor: nil) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Study tape", tableName: "Elements"))
        .accessibilityValue(covering ? Text("Covering", tableName: "Elements") : Text("Revealed", tableName: "Elements"))
        .accessibilityHint(covering ? Text("Double tap to reveal what is underneath", tableName: "Elements")
                                    : Text("Double tap to cover again", tableName: "Elements"))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { TapeToggling.toggle(element, on: page, editor: nil) }
    }
}
