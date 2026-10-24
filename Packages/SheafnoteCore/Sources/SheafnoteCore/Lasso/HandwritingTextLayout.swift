import CoreGraphics
import Foundation

/// Where and how large the text box goes when handwriting is converted to text.
public enum HandwritingTextLayout {
    public static let minimumFontSize: Double = 12
    public static let maximumFontSize: Double = 48
    static let lineSpacing: Double = 1.3

    public struct Result: Equatable, Sendable {
        public var frame: CGRect
        public var fontSize: Double
    }

    /// The text replaces the handwriting in place: same top-left corner, a font sized from the height of one written
    /// line, and a frame wide enough to avoid wrapping short text.
    public static func layout(text: String, over bounds: CGRect, pageSize: CGSize) -> Result {
        let lines = max(text.split(separator: "\n", omittingEmptySubsequences: false).count, 1)
        let perLine = Double(bounds.height) / Double(lines)
        let fontSize = min(max(perLine * 0.62, minimumFontSize), maximumFontSize)
        let longest = text.split(separator: "\n").map(\.count).max() ?? 1
        let estimatedWidth = CGFloat(fontSize * 0.55 * Double(longest)) + 16
        var width = max(bounds.width, estimatedWidth, 80)
        width = min(width, max(pageSize.width - bounds.minX, 80))
        let height = max(CGFloat(fontSize * lineSpacing * Double(lines)) + 8, 28)
        let x = max(min(bounds.minX, pageSize.width - width), 0)
        let y = max(min(bounds.minY, pageSize.height - height), 0)
        return Result(frame: CGRect(x: x, y: y, width: width, height: height), fontSize: fontSize)
    }
}
