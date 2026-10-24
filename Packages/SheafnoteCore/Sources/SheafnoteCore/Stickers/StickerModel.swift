import CoreGraphics
import Foundation

/// One drawing step of a sticker outline, in the sticker's own design space (origin top-left, y down).
public enum StickerCommand: Hashable, Sendable {
    case move(CGPoint)
    case line(CGPoint)
    case quad(to: CGPoint, control: CGPoint)
    case curve(to: CGPoint, control1: CGPoint, control2: CGPoint)
    case close
}

/// A color slot. `primary` and `secondary` follow the user's tint; the rest are fixed.
public enum StickerPaint: Hashable, Sendable {
    case primary
    case secondary
    case white
    case black
    case fixed(String)
}

public struct StickerLayer: Hashable, Sendable {
    public var commands: [StickerCommand]
    public var fill: StickerPaint?
    public var stroke: StickerPaint?
    public var lineWidth: CGFloat
    public var opacity: CGFloat
    /// Clip this layer to the sticker's first layer (used for patterns inside a washi strip).
    public var clipToBase: Bool

    public init(_ commands: [StickerCommand], fill: StickerPaint? = nil, stroke: StickerPaint? = nil,
                lineWidth: CGFloat = 0, opacity: CGFloat = 1, clipToBase: Bool = false) {
        self.commands = commands
        self.fill = fill
        self.stroke = stroke
        self.lineWidth = lineWidth
        self.opacity = opacity
        self.clipToBase = clipToBase
    }
}

public enum StickerCategory: String, CaseIterable, Codable, Sendable {
    case shapes, arrows, tabs, washi, marks
}

public struct StickerDefinition: Identifiable, Hashable, Sendable {
    public var id: String
    /// English display name; also the localization key in the `Elements` string table.
    public var name: String
    public var category: StickerCategory
    /// Design space size; the sticker stretches to its element frame.
    public var size: CGSize
    public var layers: [StickerLayer]
    public var primaryHex: String
    public var secondaryHex: String

    public init(id: String, name: String, category: StickerCategory, size: CGSize = CGSize(width: 100, height: 100),
                layers: [StickerLayer], primaryHex: String, secondaryHex: String) {
        self.id = id
        self.name = name
        self.category = category
        self.size = size
        self.layers = layers
        self.primaryHex = primaryHex
        self.secondaryHex = secondaryHex
    }

    public var aspectRatio: CGFloat { size.height > 0 ? size.width / size.height : 1 }
}
