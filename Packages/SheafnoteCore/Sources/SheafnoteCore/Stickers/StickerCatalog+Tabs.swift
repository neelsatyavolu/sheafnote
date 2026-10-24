import CoreGraphics
import Foundation

extension StickerCatalog {
    static let tabs: [StickerDefinition] = [
        make("tab-top", "Index Tab", .tabs, size: CGSize(width: 80, height: 44), primary: "#E86F6F", secondary: "#B14444", [
            solid([
                .move(pt(2, 42)), .line(pt(2, 16)),
                .curve(to: pt(16, 2), control1: pt(2, 8), control2: pt(8, 2)),
                .line(pt(64, 2)),
                .curve(to: pt(78, 16), control1: pt(72, 2), control2: pt(78, 8)),
                .line(pt(78, 42)), .close,
            ]),
            line(P.polyline([pt(18, 24), pt(62, 24)]), paint: .white, width: 5, opacity: 0.7),
        ]),
        make("tab-side", "Side Tab", .tabs, size: CGSize(width: 44, height: 80), primary: "#4FA6C9", secondary: "#2A7596", [
            solid([
                .move(pt(42, 2)), .line(pt(16, 2)),
                .curve(to: pt(2, 16), control1: pt(8, 2), control2: pt(2, 8)),
                .line(pt(2, 64)),
                .curve(to: pt(16, 78), control1: pt(2, 72), control2: pt(8, 78)),
                .line(pt(42, 78)), .close,
            ]),
            line(P.polyline([pt(22, 18), pt(22, 62)]), paint: .white, width: 5, opacity: 0.7),
        ]),
        make("folder", "Folder Tab", .tabs, size: CGSize(width: 100, height: 76), primary: "#EBB63D", secondary: "#B88415", [
            flat(P.roundedRect(CGRect(x: 4, y: 6, width: 42, height: 26), radius: 7)),
            flat(P.roundedRect(CGRect(x: 4, y: 20, width: 92, height: 52), radius: 8)),
            StickerLayer(P.roundedRect(CGRect(x: 4, y: 34, width: 92, height: 38), radius: 8), fill: .white, opacity: 0.22),
        ]),
        make("ribbon", "Bookmark Ribbon", .tabs, size: CGSize(width: 50, height: 100), primary: "#D8584F", secondary: "#9F2F28", [
            solid(P.polygon([pt(8, 4), pt(42, 4), pt(42, 96), pt(25, 78), pt(8, 96)])),
        ]),
        make("flag", "Flag", .tabs, primary: "#4DAE7C", secondary: "#2C7A52", [
            line(P.polyline([pt(22, 8), pt(22, 94)]), paint: .fixed("#5B4636"), width: 6),
            solid(P.polygon([pt(25, 10), pt(86, 30), pt(25, 52)])),
        ]),
        make("note", "Sticky Note", .tabs, primary: "#F6DD6B", secondary: "#C8A93A", [
            flat(P.polygon([pt(6, 6), pt(94, 6), pt(94, 64), pt(64, 94), pt(6, 94)])),
            StickerLayer(P.polygon([pt(94, 64), pt(64, 94), pt(64, 64)]), fill: .secondary, opacity: 0.55),
        ]),
        make("tag", "Label Tag", .tabs, size: CGSize(width: 100, height: 60), primary: "#9C7BD9", secondary: "#6B4BAA", [
            solid(P.polygon([pt(6, 6), pt(68, 6), pt(94, 30), pt(68, 54), pt(6, 54)])),
            dot(72, 30, radius: 6),
        ]),
    ]
}
