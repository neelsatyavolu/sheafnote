import CoreGraphics
import Foundation

/// Draws covers with CoreGraphics. TOP-LEFT origin context (UIKit / SwiftUI Canvas), portrait 3:4 recommended.
public enum CoverRenderer {
    public static func draw(_ cover: CoverDefinition, size: CGSize, in ctx: CGContext) {
        let rect = CGRect(origin: .zero, size: size)
        ctx.saveGState()
        ctx.clip(to: rect)
        drawBackground(cover, rect, ctx)
        drawPattern(cover, rect, ctx)
        drawFrame(cover, rect, ctx)
        drawSpine(rect, ctx)
        drawGrain(rect, ctx)
        ctx.restoreGState()
    }

    public static func renderImage(_ cover: CoverDefinition, size: CGSize, scale: CGFloat = 1) -> CGImage? {
        let w = max(1, Int((size.width * scale).rounded())), h = max(1, Int((size.height * scale).rounded()))
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: scale, y: -scale)
        draw(cover, size: size, in: ctx)
        return ctx.makeImage()
    }

    // MARK: Layers

    private static func drawBackground(_ c: CoverDefinition, _ r: CGRect, _ ctx: CGContext) {
        if let end = c.backgroundEnd,
           let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                              colors: [c.background.cgColor, end.cgColor] as CFArray, locations: [0, 1]) {
            ctx.drawLinearGradient(g, start: CGPoint(x: r.midX, y: r.minY), end: CGPoint(x: r.midX, y: r.maxY), options: [])
        } else {
            ctx.setFillColor(c.background.cgColor)
            ctx.fill(r)
        }
    }

    private static func drawFrame(_ c: CoverDefinition, _ r: CGRect, _ ctx: CGContext) {
        guard c.pattern == .solid else { return }
        let inset = r.width * 0.07
        ctx.setStrokeColor(c.accent.withAlpha(0.55).cgColor)
        ctx.setLineWidth(max(1, r.width * 0.006))
        ctx.stroke(r.insetBy(dx: inset, dy: inset))
    }

    /// Darker stripe along the binding edge, with a thin highlight on its inner side.
    private static func drawSpine(_ r: CGRect, _ ctx: CGContext) {
        let w = r.width * 0.075
        ctx.setFillColor(CGColor(srgbRed: 0.17, green: 0.14, blue: 0.12, alpha: 0.34))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: r.height))
        ctx.setFillColor(CGColor(gray: 1, alpha: 0.16))
        ctx.fill(CGRect(x: w, y: 0, width: max(1, r.width * 0.008), height: r.height))
    }

    /// Faint, deterministic paper grain: tiny warm specks at very low opacity.
    private static func drawGrain(_ r: CGRect, _ ctx: CGContext) {
        let speck = max(0.5, r.width / 220)
        let count = min(4000, Int(r.width * r.height / 90))
        var state: UInt64 = 0x9E37_79B9_7F4A_7C15
        func next() -> CGFloat {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return CGFloat(state >> 40) / CGFloat(1 << 24)
        }
        for i in 0..<count {
            let x = next() * r.width, y = next() * r.height
            let light = i % 2 == 0
            ctx.setFillColor(light ? CGColor(gray: 1, alpha: 0.07) : CGColor(srgbRed: 0.17, green: 0.14, blue: 0.12, alpha: 0.06))
            ctx.fill(CGRect(x: x, y: y, width: speck, height: speck))
        }
    }

    private static func drawPattern(_ c: CoverDefinition, _ r: CGRect, _ ctx: CGContext) {
        let u = r.width / 12      // pattern cell
        ctx.setFillColor(c.ink.cgColor)
        ctx.setStrokeColor(c.ink.cgColor)
        switch c.pattern {
        case .solid: break
        case .stripes: stripes(c, r, u, ctx)
        case .diagonal: diagonal(r, u, ctx)
        case .dots: dots(c, r, u, ctx)
        case .grid: gridLines(r, u, ctx)
        case .waves: waves(r, u, ctx)
        case .rings: rings(c, r, ctx)
        case .checker: checker(r, u, ctx)
        case .triangles: triangles(c, r, ctx)
        case .chevrons: chevrons(r, u, ctx)
        case .sunburst: sunburst(c, r, ctx)
        case .scales: scales(c, r, u, ctx)
        case .bands: bands(c, r, ctx)
        }
    }

    private static func stripes(_ c: CoverDefinition, _ r: CGRect, _ u: CGFloat, _ ctx: CGContext) {
        var x = u * 1.5
        while x < r.width {
            ctx.fill(CGRect(x: x, y: 0, width: u * 0.35, height: r.height))
            x += u * 1.1
        }
        ctx.setFillColor(c.accent.cgColor)
        ctx.fill(CGRect(x: 0, y: r.height * 0.78, width: r.width, height: u * 0.5))
    }

    private static func diagonal(_ r: CGRect, _ u: CGFloat, _ ctx: CGContext) {
        ctx.setLineWidth(u * 0.5)
        var x = -r.height
        while x < r.width {
            ctx.move(to: CGPoint(x: x, y: r.height))
            ctx.addLine(to: CGPoint(x: x + r.height, y: 0))
            x += u * 1.4
        }
        ctx.strokePath()
    }

    private static func dots(_ c: CoverDefinition, _ r: CGRect, _ u: CGFloat, _ ctx: CGContext) {
        var row = 0
        var y = u * 0.8
        while y < r.height + u {
            var x = (row % 2 == 0 ? u * 0.8 : u * 1.6)
            var col = 0
            while x < r.width + u {
                ctx.setFillColor((((row + col) % 5 == 0) ? c.accent : c.ink).cgColor)
                ctx.fillEllipse(in: CGRect(x: x - u * 0.28, y: y - u * 0.28, width: u * 0.56, height: u * 0.56))
                x += u * 1.6; col += 1
            }
            y += u * 1.3; row += 1
        }
    }

    private static func gridLines(_ r: CGRect, _ u: CGFloat, _ ctx: CGContext) {
        ctx.setLineWidth(max(0.6, u * 0.06))
        var x = u
        while x < r.width { ctx.move(to: CGPoint(x: x, y: 0)); ctx.addLine(to: CGPoint(x: x, y: r.height)); x += u }
        var y = u
        while y < r.height { ctx.move(to: CGPoint(x: 0, y: y)); ctx.addLine(to: CGPoint(x: r.width, y: y)); y += u }
        ctx.strokePath()
    }

    private static func waves(_ r: CGRect, _ u: CGFloat, _ ctx: CGContext) {
        ctx.setLineWidth(u * 0.14)
        var y = u
        while y < r.height + u {
            ctx.move(to: CGPoint(x: 0, y: y))
            var x: CGFloat = 0
            while x < r.width {
                ctx.addQuadCurve(to: CGPoint(x: x + u, y: y), control: CGPoint(x: x + u * 0.5, y: y - u * 0.7))
                ctx.addQuadCurve(to: CGPoint(x: x + u * 2, y: y), control: CGPoint(x: x + u * 1.5, y: y + u * 0.7))
                x += u * 2
            }
            y += u * 0.9
        }
        ctx.strokePath()
    }

    private static func rings(_ c: CoverDefinition, _ r: CGRect, _ ctx: CGContext) {
        let center = CGPoint(x: r.width * 0.62, y: r.height * 0.4)
        ctx.setLineWidth(r.width * 0.018)
        for i in 1...8 {
            let rad = r.width * 0.085 * CGFloat(i)
            ctx.strokeEllipse(in: CGRect(x: center.x - rad, y: center.y - rad, width: rad * 2, height: rad * 2))
        }
        ctx.setFillColor(c.accent.cgColor)
        ctx.fillEllipse(in: CGRect(x: center.x - r.width * 0.05, y: center.y - r.width * 0.05,
                                   width: r.width * 0.1, height: r.width * 0.1))
    }

    private static func checker(_ r: CGRect, _ u: CGFloat, _ ctx: CGContext) {
        let cell = u * 1.5
        var row = 0
        var y: CGFloat = 0
        while y < r.height {
            var x: CGFloat = 0
            var col = 0
            while x < r.width {
                if (row + col) % 2 == 0 { ctx.fill(CGRect(x: x, y: y, width: cell, height: cell)) }
                x += cell; col += 1
            }
            y += cell; row += 1
        }
    }

    private static func triangles(_ c: CoverDefinition, _ r: CGRect, _ ctx: CGContext) {
        let peaks: [(CGFloat, CGFloat, CGFloat)] = [(0.1, 0.85, 0.55), (0.45, 0.85, 0.75), (0.8, 0.85, 0.5), (0.3, 0.85, 0.4)]
        for (i, p) in peaks.enumerated() {
            let w = r.width * 0.5
            let base = r.height * p.1
            let top = base - r.height * p.2 * 0.6
            ctx.beginPath()
            ctx.move(to: CGPoint(x: r.width * p.0 - w / 2, y: base))
            ctx.addLine(to: CGPoint(x: r.width * p.0, y: top))
            ctx.addLine(to: CGPoint(x: r.width * p.0 + w / 2, y: base))
            ctx.closePath()
            ctx.setFillColor(c.ink.withAlpha(0.55 + 0.15 * Double(i % 3)).cgColor)
            ctx.fillPath()
        }
        ctx.setFillColor(c.accent.cgColor)
        ctx.fillEllipse(in: CGRect(x: r.width * 0.68, y: r.height * 0.14, width: r.width * 0.14, height: r.width * 0.14))
    }

    private static func chevrons(_ r: CGRect, _ u: CGFloat, _ ctx: CGContext) {
        ctx.setLineWidth(u * 0.4)
        var y = -u
        while y < r.height + u {
            var x: CGFloat = 0
            ctx.move(to: CGPoint(x: x, y: y))
            while x < r.width + u {
                ctx.addLine(to: CGPoint(x: x + u, y: y + u))
                ctx.addLine(to: CGPoint(x: x + u * 2, y: y))
                x += u * 2
            }
            y += u * 1.1
        }
        ctx.strokePath()
    }

    private static func sunburst(_ c: CoverDefinition, _ r: CGRect, _ ctx: CGContext) {
        let center = CGPoint(x: r.midX, y: r.height * 0.72)
        let rays = 18
        let radius = r.height
        ctx.setFillColor(c.ink.withAlpha(0.35).cgColor)
        for i in 0..<rays where i % 2 == 0 {
            let a0 = CGFloat(i) / CGFloat(rays) * .pi * 2
            let a1 = CGFloat(i + 1) / CGFloat(rays) * .pi * 2
            ctx.beginPath()
            ctx.move(to: center)
            ctx.addLine(to: CGPoint(x: center.x + cos(a0) * radius, y: center.y + sin(a0) * radius))
            ctx.addLine(to: CGPoint(x: center.x + cos(a1) * radius, y: center.y + sin(a1) * radius))
            ctx.closePath()
            ctx.fillPath()
        }
        ctx.setFillColor(c.accent.cgColor)
        let sun = r.width * 0.16
        ctx.fillEllipse(in: CGRect(x: center.x - sun, y: center.y - sun, width: sun * 2, height: sun * 2))
    }

    private static func scales(_ c: CoverDefinition, _ r: CGRect, _ u: CGFloat, _ ctx: CGContext) {
        ctx.setLineWidth(u * 0.12)
        ctx.setStrokeColor(c.accent.withAlpha(0.7).cgColor)
        var row = 0
        var y = u
        while y < r.height + u * 2 {
            var x = row % 2 == 0 ? CGFloat(0) : -u
            while x < r.width + u * 2 {
                ctx.addArc(center: CGPoint(x: x + u, y: y), radius: u, startAngle: .pi, endAngle: 0, clockwise: true)
                ctx.strokePath()
                x += u * 2
            }
            y += u * 0.55; row += 1
        }
    }

    private static func bands(_ c: CoverDefinition, _ r: CGRect, _ ctx: CGContext) {
        let heights: [CGFloat] = [0.18, 0.12, 0.24, 0.1]
        var y = r.height * 0.1
        for (i, h) in heights.enumerated() {
            ctx.setFillColor((i % 2 == 0 ? c.ink : c.accent).cgColor)
            ctx.fill(CGRect(x: 0, y: y, width: r.width, height: r.height * h))
            y += r.height * (h + 0.06)
        }
    }
}
