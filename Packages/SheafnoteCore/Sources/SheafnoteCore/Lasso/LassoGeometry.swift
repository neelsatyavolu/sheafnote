import CoreGraphics
import Foundation

/// Pure geometry for the lasso tool: cleaning up the drawn path and testing it against ink and outlines.
public enum LassoGeometry {
    /// A lasso enclosing less than this area (points squared) is treated as a tap.
    public static let minimumArea: CGFloat = 400
    /// A drag that never travels farther than this (points) is a tap.
    public static let tapDistance: CGFloat = 8
    /// Points closer than this to their predecessor add nothing to the path.
    static let minimumPointSpacing: CGFloat = 1.5
    static let simplifyTolerance: CGFloat = 0.75
    static let maximumPoints = 240

    /// The drag as a closed polygon, or nil when it is a tap, a line, or too small to enclose anything.
    public static func closedPolygon(from samples: [CGPoint]) -> [CGPoint]? {
        guard !isTap(samples) else { return nil }
        var points = ShapeFit.dedupe(samples, minDistance: minimumPointSpacing)
        points = ShapeFit.rdp(points, epsilon: simplifyTolerance)
        if points.count > maximumPoints { points = ShapeFit.rdp(points, epsilon: simplifyTolerance * 4) }
        guard points.count >= 3, ShapeFit.polygonArea(points) >= minimumArea else { return nil }
        return points
    }

    public static func isTap(_ samples: [CGPoint]) -> Bool {
        guard let first = samples.first else { return true }
        return samples.allSatisfy { ShapeFit.distance($0, first) <= tapDistance }
    }

    public static func area(of polygon: [CGPoint]) -> CGFloat { ShapeFit.polygonArea(polygon) }

    /// True when a polyline (a stroke's sampled points, a shape outline) touches the lasso polygon: a point inside it
    /// or a segment crossing its edge.
    public static func polyline(_ line: [CGPoint], intersects polygon: [CGPoint]) -> Bool {
        guard polygon.count >= 3, !line.isEmpty else { return false }
        if line.contains(where: { PolygonMath.contains(polygon, $0) }) { return true }
        guard line.count > 1 else { return false }
        for i in 0..<(line.count - 1) {
            for j in polygon.indices where PolygonMath.segmentsIntersect(line[i], line[i + 1], polygon[j], polygon[(j + 1) % polygon.count]) {
                return true
            }
        }
        return false
    }

    /// Smallest rectangle containing every rect; nil when there are none (or all are empty).
    public static func union(_ rects: [CGRect]) -> CGRect? {
        let usable = rects.filter { !$0.isNull && !$0.isInfinite }
        guard let first = usable.first else { return nil }
        return usable.dropFirst().reduce(first) { $0.union($1) }
    }

    /// How far from a stroke or outline a tap still selects it, in page points, for the current zoom.
    public static func tapReach(zoom: CGFloat) -> CGFloat { 14 / max(zoom, 0.25) }
}

/// What the lasso picks up. Mirrors the three switches in the lasso options row.
public struct LassoFilters: OptionSet, Codable, Sendable, Hashable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    /// Pen and highlighter ink, and drawn shapes.
    public static let handwriting = LassoFilters(rawValue: 1 << 0)
    /// Images, stickers and tape.
    public static let images = LassoFilters(rawValue: 1 << 1)
    /// Text boxes and links.
    public static let text = LassoFilters(rawValue: 1 << 2)
    public static let all: LassoFilters = [.handwriting, .images, .text]

    public func accepts(_ kind: ElementKind) -> Bool {
        switch kind {
        case .shape: contains(.handwriting)
        case .image, .sticker, .tape: contains(.images)
        case .text, .link: contains(.text)
        }
    }
}
