import CoreGraphics
import Foundation

public struct StickerColors: Equatable, Sendable {
    public var primary: RGBAColor
    public var secondary: RGBAColor
}

public enum StickerPalette {
    /// The two tint-following colors of a sticker. A user tint replaces the primary color; the secondary becomes a
    /// darker shade of it so outlines stay readable.
    public static func colors(for sticker: StickerDefinition, tintHex: String?) -> StickerColors {
        let defaultPrimary = RGBAColor(hex: sticker.primaryHex) ?? RGBAColor(r: 0.5, g: 0.5, b: 0.5)
        let defaultSecondary = RGBAColor(hex: sticker.secondaryHex) ?? RGBAColor(r: 0.2, g: 0.2, b: 0.2)
        guard let tintHex, let tint = RGBAColor(hex: tintHex) else {
            return StickerColors(primary: defaultPrimary, secondary: defaultSecondary)
        }
        return StickerColors(primary: tint, secondary: darker(tint, by: 0.62))
    }

    public static func color(for paint: StickerPaint, colors: StickerColors) -> RGBAColor {
        switch paint {
        case .primary: colors.primary
        case .secondary: colors.secondary
        case .white: RGBAColor(r: 1, g: 1, b: 1)
        case .black: RGBAColor(r: 0.1, g: 0.1, b: 0.12)
        case .fixed(let hex): RGBAColor(hex: hex) ?? colors.primary
        }
    }

    static func darker(_ c: RGBAColor, by factor: Double) -> RGBAColor {
        RGBAColor(r: c.r * factor, g: c.g * factor, b: c.b * factor, a: c.a)
    }
}

/// Draws stickers into any `CGContext` whose origin is the top-left (y down): screen views, export and thumbnails.
public enum StickerRenderer {
    public static func draw(_ sticker: StickerDefinition, tintHex: String?, in ctx: CGContext, rect: CGRect) {
        guard rect.width > 0, rect.height > 0, sticker.size.width > 0, sticker.size.height > 0 else { return }
        let colors = StickerPalette.colors(for: sticker, tintHex: tintHex)
        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.translateBy(x: rect.minX, y: rect.minY)
        ctx.scaleBy(x: rect.width / sticker.size.width, y: rect.height / sticker.size.height)
        ctx.setLineJoin(.round)
        ctx.setLineCap(.round)
        let basePath = sticker.layers.first.map { cgPath($0.commands) }
        for layer in sticker.layers {
            draw(layer, in: ctx, colors: colors, base: layer.clipToBase ? basePath : nil)
        }
    }

    public static func cgPath(_ commands: [StickerCommand]) -> CGPath {
        let path = CGMutablePath()
        for command in commands {
            switch command {
            case .move(let p): path.move(to: p)
            case .line(let p): path.addLine(to: p)
            case .quad(let p, let c): path.addQuadCurve(to: p, control: c)
            case .curve(let p, let c1, let c2): path.addCurve(to: p, control1: c1, control2: c2)
            case .close: path.closeSubpath()
            }
        }
        return path
    }

    private static func draw(_ layer: StickerLayer, in ctx: CGContext, colors: StickerColors, base: CGPath?) {
        ctx.saveGState()
        defer { ctx.restoreGState() }
        if let base {
            ctx.addPath(base)
            ctx.clip()
        }
        ctx.setAlpha(layer.opacity)
        let path = cgPath(layer.commands)
        if let fill = layer.fill {
            ctx.setFillColor(StickerPalette.color(for: fill, colors: colors).cgColor)
            ctx.addPath(path)
            ctx.fillPath()
        }
        if let stroke = layer.stroke, layer.lineWidth > 0 {
            ctx.setStrokeColor(StickerPalette.color(for: stroke, colors: colors).cgColor)
            ctx.setLineWidth(layer.lineWidth)
            ctx.addPath(path)
            ctx.strokePath()
        }
    }
}
