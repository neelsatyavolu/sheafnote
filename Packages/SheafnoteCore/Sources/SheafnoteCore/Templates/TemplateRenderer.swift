import CoreGraphics
import CoreText
import Foundation

/// Draws template layouts into a CGContext. The context must have a TOP-LEFT origin
/// (UIKit-style). For PDF contexts (bottom-left) call `drawFlipped`.
public enum TemplateRenderer {
    public static func draw(_ spec: TemplateSpec, size: CGSize, paper: PaperColor, in ctx: CGContext,
                            includePaper: Bool = true, strings: TemplateStrings = .english) {
        let palette = PaperPalette.palette(for: paper)
        ctx.saveGState()
        defer { ctx.restoreGState() }
        if includePaper {
            ctx.setFillColor(palette.paper.cgColor)
            ctx.fill(CGRect(origin: .zero, size: size))
        }
        let layout = TemplateLayoutBuilder.layout(for: spec, size: size, strings: strings)
        ctx.setLineCap(.butt)
        for prim in layout.primitives { draw(prim, palette: palette, in: ctx) }
    }

    /// For contexts whose origin is bottom-left (PDF, bitmap): flips then draws.
    public static func drawFlipped(_ spec: TemplateSpec, size: CGSize, paper: PaperColor, in ctx: CGContext,
                                   includePaper: Bool = true, strings: TemplateStrings = .english) {
        ctx.saveGState()
        ctx.translateBy(x: 0, y: size.height)
        ctx.scaleBy(x: 1, y: -1)
        draw(spec, size: size, paper: paper, in: ctx, includePaper: includePaper, strings: strings)
        ctx.restoreGState()
    }

    /// Bitmap render (previews, tests, thumbnails). `scale` multiplies pixel size.
    public static func renderImage(_ spec: TemplateSpec, size: CGSize, paper: PaperColor, scale: CGFloat = 1,
                                   strings: TemplateStrings = .english) -> CGImage? {
        let w = max(1, Int((size.width * scale).rounded())), h = max(1, Int((size.height * scale).rounded()))
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.scaleBy(x: scale, y: scale)
        drawFlipped(spec, size: size, paper: paper, in: ctx, strings: strings)
        return ctx.makeImage()
    }

    private static func draw(_ prim: TemplatePrimitive, palette: PaperPalette, in ctx: CGContext) {
        switch prim {
        case .line(let l):
            ctx.setStrokeColor(palette.color(for: l.role).cgColor)
            ctx.setLineWidth(l.weight.width)
            ctx.move(to: l.start)
            ctx.addLine(to: l.end)
            ctx.strokePath()
        case .box(let b):
            ctx.setStrokeColor(palette.color(for: b.role).cgColor)
            ctx.setLineWidth(b.weight.width)
            ctx.stroke(b.rect)
        case .dot(let d):
            ctx.setFillColor(palette.major.cgColor)
            ctx.fillEllipse(in: CGRect(x: d.center.x - d.radius, y: d.center.y - d.radius,
                                       width: d.radius * 2, height: d.radius * 2))
        case .label(let l):
            drawLabel(l, color: palette.text, in: ctx)
        }
    }

    private static func drawLabel(_ l: TemplateLabel, color: RGBAColor, in ctx: CGContext) {
        let font = CTFontCreateUIFontForLanguage(.system, l.fontSize, nil)
            ?? CTFontCreateWithName("Helvetica" as CFString, l.fontSize, nil)
        let attrs: [CFString: Any] = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: color.cgColor]
        let str = CFAttributedStringCreate(nil, l.text as CFString, attrs as CFDictionary)!
        let line = CTLineCreateWithAttributedString(str)
        ctx.saveGState()
        ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        ctx.textPosition = CGPoint(x: l.origin.x, y: l.origin.y + CTFontGetAscent(font))
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }
}
