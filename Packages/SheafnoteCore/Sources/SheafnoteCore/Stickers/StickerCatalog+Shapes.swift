import CoreGraphics
import Foundation

extension StickerCatalog {
    static let shapes: [StickerDefinition] = [
        make("star", "Star", .shapes, primary: "#FFC93C", secondary: "#B8912B", [
            solid(P.star(center: pt(50, 53), outer: 46, inner: 20, points: 5)),
        ]),
        make("heart", "Heart", .shapes, primary: "#FF6FA8", secondary: "#B85079", [
            solid([
                .move(pt(50, 88)),
                .curve(to: pt(20, 20), control1: pt(15, 60), control2: pt(5, 35)),
                .curve(to: pt(50, 28), control1: pt(33, 8), control2: pt(47, 14)),
                .curve(to: pt(80, 20), control1: pt(53, 14), control2: pt(67, 8)),
                .curve(to: pt(50, 88), control1: pt(95, 35), control2: pt(85, 60)),
                .close,
            ]),
        ]),
        make("circle", "Circle", .shapes, primary: "#3CC9A0", secondary: "#2B9173", [
            solid(P.ellipse(in: CGRect(x: 6, y: 6, width: 88, height: 88))),
        ]),
        make("square", "Rounded Square", .shapes, primary: "#3D9BFF", secondary: "#2C70B8", [
            solid(P.roundedRect(CGRect(x: 8, y: 8, width: 84, height: 84), radius: 16)),
        ]),
        make("triangle", "Triangle", .shapes, primary: "#F2542D", secondary: "#AE3C20", [
            solid(P.polygon([pt(50, 8), pt(94, 86), pt(6, 86)])),
        ]),
        make("hexagon", "Hexagon", .shapes, primary: "#A77BFF", secondary: "#7859B8", [
            solid(P.regularPolygon(center: pt(50, 50), radius: 46, sides: 6)),
        ]),
        make("diamond", "Diamond", .shapes, primary: "#3D9BFF", secondary: "#2C70B8", [
            solid(P.polygon([pt(50, 6), pt(90, 50), pt(50, 94), pt(10, 50)])),
        ]),
        make("cloud", "Cloud", .shapes, primary: "#3D9BFF", secondary: "#2C70B8", [
            flat(P.ellipse(in: CGRect(x: 8, y: 42, width: 38, height: 38))),
            flat(P.ellipse(in: CGRect(x: 26, y: 20, width: 46, height: 46))),
            flat(P.ellipse(in: CGRect(x: 52, y: 32, width: 40, height: 40))),
            flat(P.roundedRect(CGRect(x: 18, y: 50, width: 66, height: 30), radius: 15)),
            StickerLayer(P.ellipse(in: CGRect(x: 34, y: 28, width: 18, height: 12)), fill: .white, opacity: 0.45),
        ]),
        make("burst", "Burst", .shapes, primary: "#FFC93C", secondary: "#B8912B", [
            solid(P.star(center: pt(50, 50), outer: 48, inner: 35, points: 12)),
        ]),
        make("bubble", "Speech Bubble", .shapes, primary: "#3CC9A0", secondary: "#2B9173", [
            flat(P.roundedRect(CGRect(x: 6, y: 10, width: 88, height: 62), radius: 16)),
            flat(P.polygon([pt(24, 66), pt(22, 92), pt(52, 68)])),
            dot(32, 41, radius: 5, opacity: 0.9),
            dot(50, 41, radius: 5, opacity: 0.9),
            dot(68, 41, radius: 5, opacity: 0.9),
        ]),
        make("sun", "Sun", .shapes, primary: "#FFC93C", secondary: "#B8912B", [
            solid(P.ellipse(in: CGRect(x: 28, y: 28, width: 44, height: 44))),
        ] + (0..<8).map { i -> StickerLayer in
            let a = CGFloat(i) * .pi / 4
            return line(P.polyline([pt(50 + 33 * cos(a), 50 + 33 * sin(a)), pt(50 + 45 * cos(a), 50 + 45 * sin(a))]), width: 7)
        }),
        make("moon", "Crescent Moon", .shapes, primary: "#FFC93C", secondary: "#B8912B", [
            solid([
                .move(pt(60, 8)),
                .curve(to: pt(14, 56), control1: pt(30, 12), control2: pt(12, 32)),
                .curve(to: pt(64, 92), control1: pt(16, 80), control2: pt(40, 94)),
                .curve(to: pt(60, 8), control1: pt(38, 78), control2: pt(34, 34)),
                .close,
            ]),
        ]),
        make("bolt", "Lightning Bolt", .shapes, primary: "#FFC93C", secondary: "#B8912B", [
            solid(P.polygon([pt(58, 6), pt(22, 56), pt(46, 56), pt(38, 94), pt(78, 40), pt(54, 40)])),
        ]),
        make("drop", "Water Drop", .shapes, primary: "#3D9BFF", secondary: "#2C70B8", [
            solid([
                .move(pt(50, 6)),
                .curve(to: pt(16, 64), control1: pt(50, 6), control2: pt(16, 46)),
                .curve(to: pt(50, 94), control1: pt(16, 82), control2: pt(31, 94)),
                .curve(to: pt(84, 64), control1: pt(69, 94), control2: pt(84, 82)),
                .curve(to: pt(50, 6), control1: pt(84, 46), control2: pt(50, 6)),
                .close,
            ]),
            StickerLayer(P.ellipse(in: CGRect(x: 30, y: 56, width: 10, height: 18)), fill: .white, opacity: 0.5),
        ]),
        make("flower", "Flower", .shapes, primary: "#FF6FA8", secondary: "#B85079", flowerLayers()),
    ]

    private static func flowerLayers() -> [StickerLayer] {
        let petals = (0..<5).map { i -> StickerLayer in
            let a = -CGFloat.pi / 2 + CGFloat(i) * 2 * .pi / 5
            let c = pt(50 + 25 * cos(a), 50 + 25 * sin(a))
            return solid(P.ellipse(in: CGRect(x: c.x - 18, y: c.y - 18, width: 36, height: 36)), width: 2)
        }
        return petals + [dot(50, 50, radius: 14, paint: .fixed("#F7D046"))]
    }
}
