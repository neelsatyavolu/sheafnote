import SwiftUI
import UIKit
import SheafnoteCore

/// Draws `ElementKind.shape` elements, live and for export.
///
/// Shapes sit below the ink (`.belowInk`) on purpose: a filled shape above the ink would hide handwriting, and the
/// above-ink layer takes touches over every element's bounds, which would stop the pen inside a drawn rectangle.
/// Change `slot` here if the layer rules change.
@MainActor
final class ShapeElementRenderer: ElementRenderer {
    let kind = ElementKind.shape
    let slot = PageLayerSlot.belowInk

    func makeView(for element: ElementValue, page: PageContext) -> AnyView {
        AnyView(ShapeElementView(element: element))
    }

    func draw(_ element: ElementValue, into ctx: CGContext, assets: AssetResolver, options: RenderOptions) async throws {
        guard let payload = PayloadCodec.decode(ShapePayload.self, from: element.payload),
              let figure = ShapeElementGeometry.localFigure(of: element) else { return }
        let width = CGFloat(payload.lineWidth)
        let path = ShapeCGPath.drawingPath(for: figure, lineWidth: width)
        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.translateBy(x: element.frame.midX, y: element.frame.midY)
        ctx.rotate(by: CGFloat(element.rotation))
        ctx.translateBy(x: -element.frame.width / 2, y: -element.frame.height / 2)
        if let fill = payload.fillHex, figure.isClosed {
            ctx.addPath(path)
            ctx.setFillColor(UIColor(hex: fill).cgColor)
            ctx.fillPath()
        }
        ctx.addPath(path)
        ctx.setStrokeColor(UIColor(hex: payload.strokeHex).cgColor)
        ctx.setLineWidth(width)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.strokePath()
    }

    func hitTester(for element: ElementValue) -> any ElementHitTesting { ShapeHitTester(element: element) }

    func beginEditing(_ element: ElementValue, page: PageContext, editor: EditorContext) {
        editor.selection.select(pageID: page.pageID, strokeIDs: [], elementIDs: [element.id],
                                bounds: ShapeHitTester(element: element).bounds)
    }
}

/// The live view of a shape: laid out by the element layer at the element's frame, rotation and position.
struct ShapeElementView: View {
    let element: ElementValue

    var body: some View {
        if let payload = PayloadCodec.decode(ShapePayload.self, from: element.payload),
           let figure = ShapeElementGeometry.localFigure(of: element) {
            let path = Path(ShapeCGPath.drawingPath(for: figure, lineWidth: CGFloat(payload.lineWidth)))
            ZStack(alignment: .topLeading) {
                if let fill = payload.fillHex, figure.isClosed { path.fill(Color(hex: fill)) }
                path.stroke(Color(hex: payload.strokeHex),
                            style: StrokeStyle(lineWidth: CGFloat(payload.lineWidth), lineCap: .round, lineJoin: .round))
            }
            .frame(width: element.frame.width, height: element.frame.height, alignment: .topLeading)
            .allowsHitTesting(false)
            .accessibilityElement()
            .accessibilityLabel(Text(ShapeNames.title(for: figure.kind)))
        } else {
            Color.clear.accessibilityHidden(true)
        }
    }
}

enum ShapeNames {
    static func title(for kind: ShapeKind) -> LocalizedStringResource {
        switch kind {
        case .line: LocalizedStringResource("Line", table: "InkTools")
        case .arrow: LocalizedStringResource("Arrow", table: "InkTools")
        case .rectangle: LocalizedStringResource("Rectangle", table: "InkTools")
        case .ellipse: LocalizedStringResource("Ellipse", table: "InkTools")
        case .triangle: LocalizedStringResource("Triangle", table: "InkTools")
        case .polygon: LocalizedStringResource("Polygon", table: "InkTools")
        case .arc: LocalizedStringResource("Arc", table: "InkTools")
        }
    }

    static func title(for mode: ShapeMode) -> LocalizedStringResource {
        mode.kind.map(title(for:)) ?? LocalizedStringResource("Auto", table: "InkTools")
    }

    static func symbol(for mode: ShapeMode) -> String {
        switch mode {
        case .auto: "wand.and.stars"
        case .line: "line.diagonal"
        case .arrow: "arrow.up.right"
        case .rectangle: "rectangle"
        case .ellipse: "circle"
        case .triangle: "triangle"
        case .polygon: "hexagon"
        case .arc: "point.topleft.down.to.point.bottomright.curvepath"
        }
    }
}
