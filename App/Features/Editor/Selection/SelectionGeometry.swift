import CoreGraphics
import SheafnoteCore

/// Transform math for the selection handles. Pure functions, in page coordinates.
enum SelectionGeometry {
    static func translation(dx: CGFloat, dy: CGFloat) -> CGAffineTransform {
        CGAffineTransform(translationX: dx, y: dy)
    }

    /// Uniform scale about `anchor` so the dragged corner follows the finger. Clamped so a selection can neither
    /// vanish nor explode.
    static func scale(about anchor: CGPoint, from start: CGPoint, to current: CGPoint) -> CGAffineTransform {
        let before = hypot(start.x - anchor.x, start.y - anchor.y)
        guard before > 0.001 else { return .identity }
        let after = hypot(current.x - anchor.x, current.y - anchor.y)
        let s = min(max(after / before, 0.1), 20)
        return about(anchor, CGAffineTransform(scaleX: s, y: s))
    }

    static func rotation(about center: CGPoint, from start: CGPoint, to current: CGPoint) -> CGAffineTransform {
        let a0 = atan2(start.y - center.y, start.x - center.x)
        let a1 = atan2(current.y - center.y, current.x - center.x)
        return about(center, CGAffineTransform(rotationAngle: a1 - a0))
    }

    static func about(_ point: CGPoint, _ t: CGAffineTransform) -> CGAffineTransform {
        CGAffineTransform(translationX: -point.x, y: -point.y).concatenating(t).concatenating(CGAffineTransform(translationX: point.x, y: point.y))
    }

    static func corners(of rect: CGRect, under t: CGAffineTransform) -> [CGPoint] {
        [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
         CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY)].map { $0.applying(t) }
    }

    static func bounds(of rect: CGRect, under t: CGAffineTransform) -> CGRect {
        PolygonMath.bounds(of: corners(of: rect, under: t))
    }
}
