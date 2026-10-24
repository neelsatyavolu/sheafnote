import CoreGraphics
import Foundation

/// The built-in sticker set. Every sticker is original path data drawn by `StickerRenderer`; nothing is copied artwork.
public enum StickerCatalog {
    public static let all: [StickerDefinition] = shapes + arrows + tabs + washi + marks

    public static func stickers(in category: StickerCategory) -> [StickerDefinition] {
        all.filter { $0.category == category }
    }

    public static func sticker(id: String) -> StickerDefinition? { byID[id] }

    private static let byID: [String: StickerDefinition] = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
}

extension StickerCatalog {
    typealias P = StickerPathBuilder

    static func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

    static func make(_ id: String, _ name: String, _ category: StickerCategory, size: CGSize = CGSize(width: 100, height: 100),
                 primary: String, secondary: String, _ layers: [StickerLayer]) -> StickerDefinition {
        StickerDefinition(id: id, name: name, category: category, size: size, layers: layers,
                          primaryHex: primary, secondaryHex: secondary)
    }

    /// Fill with the primary color and an outline in the secondary color.
    static func solid(_ commands: [StickerCommand], width: CGFloat = 3) -> StickerLayer {
        StickerLayer(commands, fill: .primary, stroke: .secondary, lineWidth: width)
    }

    /// Fill with the primary color only.
    static func flat(_ commands: [StickerCommand], opacity: CGFloat = 1) -> StickerLayer {
        StickerLayer(commands, fill: .primary, opacity: opacity)
    }

    /// A stroked line in the given paint.
    static func line(_ commands: [StickerCommand], paint: StickerPaint = .primary, width: CGFloat, opacity: CGFloat = 1,
              clip: Bool = false) -> StickerLayer {
        StickerLayer(commands, stroke: paint, lineWidth: width, opacity: opacity, clipToBase: clip)
    }

    static func dot(_ x: CGFloat, _ y: CGFloat, radius: CGFloat, paint: StickerPaint = .white, opacity: CGFloat = 1,
             clip: Bool = false) -> StickerLayer {
        StickerLayer(P.ellipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)),
                     fill: paint, opacity: opacity, clipToBase: clip)
    }

}
