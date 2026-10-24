import CoreGraphics
import Foundation

extension StickerCatalog {
    private static let disc = CGRect(x: 6, y: 6, width: 88, height: 88)

    static let marks: [StickerDefinition] = [
        make("check", "Check Mark", .marks, primary: "#3CC9A0", secondary: "#2B9173", [
            solid(P.ellipse(in: disc)),
            line(P.polyline([pt(28, 52), pt(44, 68), pt(74, 34)]), paint: .white, width: 10),
        ]),
        make("cross", "Cross Mark", .marks, primary: "#F2542D", secondary: "#AE3C20", [
            solid(P.ellipse(in: disc)),
            line(P.polyline([pt(32, 32), pt(68, 68)]), paint: .white, width: 10),
            line(P.polyline([pt(68, 32), pt(32, 68)]), paint: .white, width: 10),
        ]),
        make("question", "Question Mark", .marks, primary: "#3D9BFF", secondary: "#2C70B8", [
            solid(P.ellipse(in: disc)),
            line([.move(pt(36, 38)), .curve(to: pt(64, 38), control1: pt(36, 18), control2: pt(64, 18)),
                  .curve(to: pt(50, 60), control1: pt(64, 50), control2: pt(50, 50))], paint: .white, width: 8),
            dot(50, 76, radius: 5.5),
        ]),
        make("exclamation", "Exclamation Mark", .marks, primary: "#FFC93C", secondary: "#B8912B", [
            solid(P.ellipse(in: disc)),
            line(P.polyline([pt(50, 26), pt(50, 56)]), paint: .white, width: 10),
            dot(50, 74, radius: 5.5),
        ]),
        make("pin", "Map Pin", .marks, primary: "#F2542D", secondary: "#AE3C20", [
            solid([
                .move(pt(50, 94)),
                .curve(to: pt(18, 38), control1: pt(50, 94), control2: pt(18, 58)),
                .curve(to: pt(50, 6), control1: pt(18, 18), control2: pt(34, 6)),
                .curve(to: pt(82, 38), control1: pt(66, 6), control2: pt(82, 18)),
                .curve(to: pt(50, 94), control1: pt(82, 58), control2: pt(50, 94)),
                .close,
            ]),
            dot(50, 38, radius: 12),
        ]),
        make("bulb", "Light Bulb", .marks, primary: "#FFC93C", secondary: "#B8912B", [
            solid(P.ellipse(in: CGRect(x: 22, y: 6, width: 56, height: 56))),
            solid(P.roundedRect(CGRect(x: 36, y: 58, width: 28, height: 12), radius: 4), width: 2),
            StickerLayer(P.roundedRect(CGRect(x: 40, y: 74, width: 20, height: 12), radius: 5), fill: .secondary),
            line(P.polyline([pt(42, 44), pt(50, 30), pt(58, 44)]), paint: .secondary, width: 3.5, opacity: 0.8),
        ]),
        make("sparkle", "Sparkle", .marks, primary: "#FFC93C", secondary: "#B8912B", [
            solid(P.star(center: pt(44, 56), outer: 40, inner: 11, points: 4)),
            flat(P.star(center: pt(80, 22), outer: 14, inner: 4, points: 4)),
        ]),
    ]
}
