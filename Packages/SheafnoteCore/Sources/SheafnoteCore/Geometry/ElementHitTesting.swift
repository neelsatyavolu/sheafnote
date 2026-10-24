import CoreGraphics
import Foundation

public protocol ElementHitTesting: Sendable {
    /// Axis-aligned, page coordinates, includes rotation.
    var bounds: CGRect { get }
    /// Lasso freeform path.
    func intersects(polygon: [CGPoint]) -> Bool
    /// Tap select.
    func contains(point: CGPoint) -> Bool
    /// Returns the moved/scaled/rotated element.
    func transformed(by t: CGAffineTransform) -> ElementValue
}

/// Default hit tester for rect-like elements: a rectangle rotated about its centre.
public struct OrientedBoxHitTester: ElementHitTesting {
    public let element: ElementValue

    public init(element: ElementValue) { self.element = element }

    public var center: CGPoint { CGPoint(x: element.frame.midX, y: element.frame.midY) }

    public var corners: [CGPoint] {
        let f = element.frame
        let c = center
        let cosA = cos(element.rotation), sinA = sin(element.rotation)
        return [CGPoint(x: f.minX, y: f.minY), CGPoint(x: f.maxX, y: f.minY),
                CGPoint(x: f.maxX, y: f.maxY), CGPoint(x: f.minX, y: f.maxY)].map { p in
            let dx = p.x - c.x, dy = p.y - c.y
            return CGPoint(x: c.x + dx * cosA - dy * sinA, y: c.y + dx * sinA + dy * cosA)
        }
    }

    public var bounds: CGRect { PolygonMath.bounds(of: corners) }

    public func contains(point: CGPoint) -> Bool {
        let c = center
        let cosA = cos(-element.rotation), sinA = sin(-element.rotation)
        let dx = point.x - c.x, dy = point.y - c.y
        let local = CGPoint(x: c.x + dx * cosA - dy * sinA, y: c.y + dx * sinA + dy * cosA)
        return element.frame.contains(local)
    }

    public func intersects(polygon: [CGPoint]) -> Bool {
        PolygonMath.overlaps(polygon: polygon, convex: corners)
    }

    public func transformed(by t: CGAffineTransform) -> ElementValue {
        var out = element
        let newCenter = center.applying(t)
        let sx = hypot(t.a, t.b)
        let sy = hypot(t.c, t.d)
        let size = CGSize(width: element.frame.width * sx, height: element.frame.height * sy)
        out.frame = CGRect(x: newCenter.x - size.width / 2, y: newCenter.y - size.height / 2,
                           width: size.width, height: size.height)
        out.rotation = element.rotation + atan2(t.b, t.a)
        return out
    }
}
