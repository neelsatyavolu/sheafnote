import CoreGraphics
import Foundation

/// Where to draw highlights on a page thumbnail. All rectangles are in unit page coordinates (0...1),
/// origin top-left, so they scale to any thumbnail size.
public enum HighlightGeometry {
    /// Vision gives one box per recognized line. The word's share of that box is estimated from its character
    /// position in the line, which is accurate enough for a highlight.
    public static func rects(for terms: [String], in lines: [RecognizedLine], padding: CGFloat = 0.004) -> [CGRect] {
        guard !terms.isEmpty else { return [] }
        var result: [CGRect] = []
        for line in lines {
            let count = max(line.text.count, 1)
            for range in SnippetBuilder.matchingRanges(in: line.text, terms: terms) {
                let box = line.boundingBox
                let x = box.minX + box.width * CGFloat(range.lowerBound) / CGFloat(count)
                let w = box.width * CGFloat(range.count) / CGFloat(count)
                let rect = CGRect(x: x, y: 1 - box.maxY, width: w, height: box.height)
                result.append(clamped(rect.insetBy(dx: -padding, dy: -padding)))
            }
        }
        return result
    }

    /// An element's frame (page points, origin top-left) as a unit rectangle.
    public static func unitRect(of frame: CGRect, pageSize: CGSize) -> CGRect {
        guard pageSize.width > 0, pageSize.height > 0 else { return .zero }
        return CGRect(x: frame.minX / pageSize.width, y: frame.minY / pageSize.height,
                      width: frame.width / pageSize.width, height: frame.height / pageSize.height)
    }

    private static func clamped(_ rect: CGRect) -> CGRect {
        rect.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
    }
}
