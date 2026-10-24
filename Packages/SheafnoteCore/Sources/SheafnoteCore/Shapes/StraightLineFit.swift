import CoreGraphics
import Foundation

/// The straight line for "draw a straight line" (highlighter) and the endpoints of a snapped line.
public enum StraightLineFit {
    /// Strokes shorter than this are left alone (a dot or a tap is not a line).
    public static let minimumLength: CGFloat = 12
    /// A line within this many degrees of horizontal or vertical is made exactly horizontal or vertical.
    public static let axisSnapDegrees: Double = 4

    /// First point to last point, snapped to the axes when close. Nil when the stroke is too short to be a line.
    public static func line(from points: [CGPoint]) -> (CGPoint, CGPoint)? {
        guard let a = points.first, let b = points.last, ShapeFit.distance(a, b) >= minimumLength else { return nil }
        return snapped(from: a, to: b)
    }

    /// Rotates the segment about its midpoint onto the nearest axis when within `axisSnapDegrees`.
    public static func snapped(from a: CGPoint, to b: CGPoint) -> (CGPoint, CGPoint) {
        let angle = ShapeFit.angle(from: a, to: b)
        let tolerance = axisSnapDegrees * .pi / 180
        let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        let half = ShapeFit.distance(a, b) / 2
        for axis in [0.0, .pi / 2, .pi, -.pi / 2] where ShapeFit.angleGap(angle, axis) <= tolerance {
            let dx = half * CGFloat(cos(axis)), dy = half * CGFloat(sin(axis))
            return (CGPoint(x: mid.x - dx, y: mid.y - dy), CGPoint(x: mid.x + dx, y: mid.y + dy))
        }
        return (a, b)
    }
}
