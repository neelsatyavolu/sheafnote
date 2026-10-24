import CoreGraphics
import Foundation

public enum PayloadCodec {
    public static func encode<T: Encodable>(_ payload: T) -> Data { JSONCoding.encode(payload) }
    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) -> T? { JSONCoding.decode(type, from: data) }
}

public enum TextAlignmentValue: String, Codable, Sendable, CaseIterable { case leading, center, trailing }

public enum LinkTarget: Codable, Hashable, Sendable {
    case page(UUID)
    case notebook(UUID)
    case url(URL)
}

public struct TextPayload: Codable, Hashable, Sendable {
    public var version: Int = 1
    public var text: String
    public var fontName: String
    public var fontSize: Double
    public var colorHex: String
    public var isBold: Bool
    public var isItalic: Bool
    public var isUnderlined: Bool
    public var alignment: TextAlignmentValue
    public var backgroundHex: String?
    public var link: LinkTarget?

    public init(text: String, fontName: String = "System", fontSize: Double = 18, colorHex: String = "#000000",
                isBold: Bool = false, isItalic: Bool = false, isUnderlined: Bool = false,
                alignment: TextAlignmentValue = .leading, backgroundHex: String? = nil, link: LinkTarget? = nil) {
        self.text = text; self.fontName = fontName; self.fontSize = fontSize; self.colorHex = colorHex
        self.isBold = isBold; self.isItalic = isItalic; self.isUnderlined = isUnderlined
        self.alignment = alignment; self.backgroundHex = backgroundHex; self.link = link
    }
}

public struct ImagePayload: Codable, Hashable, Sendable {
    public var version: Int = 1
    /// Crop in unit coordinates of the original image (origin top-left).
    public var cropRect: CGRect
    public var originalSize: CGSize

    public init(cropRect: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1), originalSize: CGSize) {
        self.cropRect = cropRect
        self.originalSize = originalSize
    }
}

public struct StickerPayload: Codable, Hashable, Sendable {
    public var version: Int = 1
    public var stickerID: String
    public var tintHex: String?

    public init(stickerID: String, tintHex: String? = nil) {
        self.stickerID = stickerID
        self.tintHex = tintHex
    }
}

public enum TapeStyle: String, Codable, Sendable, CaseIterable { case solid, striped, washi }

public struct TapePayload: Codable, Hashable, Sendable {
    public var version: Int = 1
    public var colorHex: String
    public var isRevealed: Bool
    public var style: TapeStyle

    public init(colorHex: String, isRevealed: Bool = false, style: TapeStyle = .solid) {
        self.colorHex = colorHex
        self.isRevealed = isRevealed
        self.style = style
    }
}

public struct LinkPayload: Codable, Hashable, Sendable {
    public var version: Int = 1
    public var target: LinkTarget
    public var label: String

    public init(target: LinkTarget, label: String = "") {
        self.target = target
        self.label = label
    }
}

public enum ShapeKind: String, Codable, Sendable, CaseIterable {
    case line, arrow, rectangle, ellipse, triangle, polygon, arc
}

public struct ShapePayload: Codable, Hashable, Sendable {
    public var version: Int = 1
    public var shapeKind: ShapeKind
    /// Defining points in the element's unit square (0...1), origin top-left.
    public var points: [CGPoint]
    public var strokeHex: String
    public var fillHex: String?
    public var lineWidth: Double

    public init(shapeKind: ShapeKind, points: [CGPoint], strokeHex: String = "#000000",
                fillHex: String? = nil, lineWidth: Double = 2) {
        self.shapeKind = shapeKind; self.points = points; self.strokeHex = strokeHex
        self.fillHex = fillHex; self.lineWidth = lineWidth
    }
}
