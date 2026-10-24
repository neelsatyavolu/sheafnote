import CoreGraphics
import Foundation

/// Draws one study tape into a context whose origin is the tape's top-left corner (y down).
/// A covering tape is opaque, so it hides ink and text under it. A revealed tape is a faint outline that stays
/// easy to find and tap again.
public enum TapeRenderer {
    public static let cornerRadius: CGFloat = 3

    public static func draw(_ payload: TapePayload, covering: Bool, in ctx: CGContext, size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        let color = (RGBAColor(hex: payload.colorHex) ?? RGBAColor(r: 0.9, g: 0.5, b: 0.4)).cgColor
        let shape = outline(for: payload.style, size: size)
        ctx.saveGState()
        defer { ctx.restoreGState() }
        if covering {
            ctx.addPath(shape)
            ctx.setFillColor(color)
            ctx.fillPath()
            drawPattern(payload.style, in: ctx, size: size, clip: shape)
        } else {
            ctx.addPath(shape)
            ctx.setFillColor(color.copy(alpha: 0.14) ?? color)
            ctx.fillPath()
            ctx.addPath(shape)
            ctx.setStrokeColor(color.copy(alpha: 0.75) ?? color)
            ctx.setLineWidth(1.5)
            ctx.setLineDash(phase: 0, lengths: [5, 4])
            ctx.strokePath()
        }
    }

    static func outline(for style: TapeStyle, size: CGSize) -> CGPath {
        let rect = CGRect(origin: .zero, size: size)
        switch style {
        case .solid, .striped:
            return CGPath(roundedRect: rect, cornerWidth: min(cornerRadius, size.width / 2), cornerHeight: min(cornerRadius, size.height / 2),
                          transform: nil)
        case .washi:
            let teeth = max(2, Int(size.height / 7))
            return StickerRenderer.cgPath(StickerPathBuilder.tornStrip(rect, teeth: teeth, depth: min(5, size.width / 10)))
        }
    }

    private static func drawPattern(_ style: TapeStyle, in ctx: CGContext, size: CGSize, clip: CGPath) {
        guard style != .solid else { return }
        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.addPath(clip)
        ctx.clip()
        ctx.setFillColor(CGColor(gray: 1, alpha: style == .striped ? 0.3 : 0.5))
        switch style {
        case .striped:
            var x = -size.height
            while x < size.width {
                ctx.move(to: CGPoint(x: x, y: size.height))
                ctx.addLine(to: CGPoint(x: x + 6, y: size.height))
                ctx.addLine(to: CGPoint(x: x + 6 + size.height, y: 0))
                ctx.addLine(to: CGPoint(x: x + size.height, y: 0))
                ctx.closePath()
                x += 14
            }
            ctx.fillPath()
        case .washi:
            var row = 0
            var y: CGFloat = size.height * 0.28
            while y < size.height {
                var x: CGFloat = row.isMultiple(of: 2) ? 8 : 15
                while x < size.width {
                    ctx.fillEllipse(in: CGRect(x: x - 2, y: y - 2, width: 4, height: 4))
                    x += 14
                }
                y += max(size.height * 0.44, 8)
                row += 1
            }
        case .solid:
            break
        }
    }
}
