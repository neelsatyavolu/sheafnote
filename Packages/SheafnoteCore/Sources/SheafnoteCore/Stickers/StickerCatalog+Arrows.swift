import CoreGraphics
import Foundation

extension StickerCatalog {
    private static let wide = CGSize(width: 100, height: 60)

    static let arrows: [StickerDefinition] = [
        make("arrow-right", "Block Arrow", .arrows, size: wide, primary: "#EE7B5E", secondary: "#B5492C", [
            solid(P.polygon([pt(4, 22), pt(58, 22), pt(58, 6), pt(96, 30), pt(58, 54), pt(58, 38), pt(4, 38)])),
        ]),
        make("arrow-double", "Double Arrow", .arrows, size: wide, primary: "#5E9BE0", secondary: "#2F6AAE", [
            solid(P.polygon([pt(4, 30), pt(30, 6), pt(30, 22), pt(70, 22), pt(70, 6), pt(96, 30),
                             pt(70, 54), pt(70, 38), pt(30, 38), pt(30, 54)])),
        ]),
        make("arrow-line", "Line Arrow", .arrows, size: wide, primary: "#3C4A5C", secondary: "#222B36", [
            line(P.polyline([pt(8, 30), pt(88, 30)]), width: 6),
            line(P.polyline([pt(68, 12), pt(90, 30), pt(68, 48)]), width: 6),
        ]),
        make("arrow-curved", "Curved Arrow", .arrows, primary: "#3C4A5C", secondary: "#222B36", [
            line([.move(pt(14, 82)), .curve(to: pt(84, 40), control1: pt(14, 30), control2: pt(60, 14))], width: 6),
            line(P.polyline([pt(81, 20), pt(84, 40), pt(64.5, 36)]), width: 6),
        ]),
        make("arrow-bent", "Bent Arrow", .arrows, primary: "#3C4A5C", secondary: "#222B36", [
            line(P.polyline([pt(14, 88), pt(14, 30), pt(72, 30)]), width: 6),
            line(P.polyline([pt(54, 12), pt(74, 30), pt(54, 48)]), width: 6),
        ]),
        make("chevron", "Chevron", .arrows, primary: "#E0A33A", secondary: "#A8761A", [
            line(P.polyline([pt(32, 10), pt(72, 50), pt(32, 90)]), width: 12),
        ]),
        make("arrow-banner", "Banner Arrow", .arrows, size: wide, primary: "#7A6CD6", secondary: "#4E43A3", [
            solid(P.polygon([pt(4, 10), pt(66, 10), pt(96, 30), pt(66, 50), pt(4, 50), pt(20, 30)])),
        ]),
    ]
}
