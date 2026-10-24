import CoreGraphics
import Foundation

/// A clean geometric shape in page (or element-local) coordinates. Recognition produces one; the shape element
/// stores it as a frame, a rotation and unit-square points (`ShapePlacement`).
public enum ShapeFigure: Equatable, Sendable {
    case line(from: CGPoint, to: CGPoint)
    case arrow(from: CGPoint, to: CGPoint)
    case rectangle(center: CGPoint, size: CGSize, rotation: Double)
    case ellipse(center: CGPoint, radii: CGSize, rotation: Double)
    case triangle([CGPoint])
    case polygon([CGPoint])
    /// `sweep` is signed (positive turns from +x towards +y, clockwise on screen).
    case arc(center: CGPoint, radius: CGFloat, startAngle: Double, sweep: Double)

    public var kind: ShapeKind {
        switch self {
        case .line: .line
        case .arrow: .arrow
        case .rectangle: .rectangle
        case .ellipse: .ellipse
        case .triangle: .triangle
        case .polygon: .polygon
        case .arc: .arc
        }
    }

    public var isClosed: Bool {
        switch self {
        case .rectangle, .ellipse, .triangle, .polygon: true
        case .line, .arrow, .arc: false
        }
    }

    /// An ellipse with (almost) equal radii.
    public var isCircle: Bool {
        guard case .ellipse(_, let r, _) = self else { return false }
        return abs(r.width - r.height) <= 0.01 * max(r.width, r.height)
    }
}

// MARK: Outline

public extension ShapeFigure {
    /// Head of an arrow ending at `to`: the two wing end points.
    static func arrowHead(from: CGPoint, to: CGPoint, lineWidth: CGFloat) -> (CGPoint, CGPoint) {
        let length = ShapeFit.distance(from, to)
        let head = min(max(lineWidth * 4.5, 12), max(length * 0.45, 1))
        let back = ShapeFit.angle(from: to, to: from)
        let spread = 26.0 * .pi / 180
        func wing(_ a: Double) -> CGPoint {
            CGPoint(x: to.x + head * CGFloat(cos(a)), y: to.y + head * CGFloat(sin(a)))
        }
        return (wing(back + spread), wing(back - spread))
    }

    /// Corner points of a rotated rectangle, clockwise from the top-left corner before rotation.
    static func rectangleCorners(center: CGPoint, size: CGSize, rotation: Double) -> [CGPoint] {
        let hw = size.width / 2, hh = size.height / 2
        let c = CGFloat(cos(rotation)), s = CGFloat(sin(rotation))
        return [(-hw, -hh), (hw, -hh), (hw, hh), (-hw, hh)].map { x, y in
            CGPoint(x: center.x + x * c - y * s, y: center.y + x * s + y * c)
        }
    }

    /// Sampled outline as one continuous pen path (closed shapes return to their first point; an arrow includes its
    /// head). `spacing` is the distance between samples on straight parts, in points.
    func outline(spacing: CGFloat = 3, arrowLineWidth: CGFloat = 3) -> [CGPoint] {
        switch self {
        case .line(let a, let b):
            return Self.sample(polyline: [a, b], spacing: spacing)
        case .arrow(let a, let b):
            let (w1, w2) = Self.arrowHead(from: a, to: b, lineWidth: arrowLineWidth)
            return Self.sample(polyline: [a, b, w1, b, w2], spacing: spacing)
        case .rectangle(let c, let s, let r):
            let corners = Self.rectangleCorners(center: c, size: s, rotation: r)
            return Self.sample(polyline: corners + [corners[0]], spacing: spacing)
        case .ellipse(let c, let radii, let r):
            return Self.ellipsePoints(center: c, radii: radii, rotation: r, spacing: spacing)
        case .triangle(let p), .polygon(let p):
            guard let first = p.first else { return [] }
            return Self.sample(polyline: p + [first], spacing: spacing)
        case .arc(let c, let radius, let start, let sweep):
            return Self.arcPoints(center: c, radius: radius, start: start, sweep: sweep, spacing: spacing)
        }
    }

    /// Bounding box of the outline.
    var bounds: CGRect { PolygonMath.bounds(of: outline(spacing: 6)) }

    /// The stroke segments to test or draw, as polylines (closed shapes repeat their first point).
    func polylines(arrowLineWidth: CGFloat = 3) -> [[CGPoint]] {
        switch self {
        case .arrow(let a, let b):
            let (w1, w2) = Self.arrowHead(from: a, to: b, lineWidth: arrowLineWidth)
            return [[a, b], [w1, b, w2]]
        default:
            return [outline(spacing: 6, arrowLineWidth: arrowLineWidth)]
        }
    }

    internal static func sample(polyline: [CGPoint], spacing: CGFloat) -> [CGPoint] {
        guard let first = polyline.first else { return [] }
        var out = [first]
        for (a, b) in zip(polyline, polyline.dropFirst()) {
            let steps = max(1, Int((ShapeFit.distance(a, b) / max(spacing, 0.5)).rounded(.up)))
            for i in 1...steps {
                let t = CGFloat(i) / CGFloat(steps)
                out.append(CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
            }
        }
        return out
    }

    internal static func ellipsePoints(center: CGPoint, radii: CGSize, rotation: Double, spacing: CGFloat) -> [CGPoint] {
        let perimeter = 2 * .pi * Double((radii.width + radii.height) / 2)
        let count = max(48, Int(perimeter / Double(max(spacing, 0.5))))
        let c = CGFloat(cos(rotation)), s = CGFloat(sin(rotation))
        return (0...count).map { i in
            let a = 2 * Double.pi * Double(i) / Double(count)
            let x = radii.width * CGFloat(cos(a)), y = radii.height * CGFloat(sin(a))
            return CGPoint(x: center.x + x * c - y * s, y: center.y + x * s + y * c)
        }
    }

    internal static func arcPoints(center: CGPoint, radius: CGFloat, start: Double, sweep: Double, spacing: CGFloat) -> [CGPoint] {
        let length = Double(radius) * abs(sweep)
        let count = max(12, Int(length / Double(max(spacing, 0.5))), Int(abs(sweep) / (1.5 * .pi / 180)))
        return (0...count).map { i in
            let a = start + sweep * Double(i) / Double(count)
            return CGPoint(x: center.x + radius * CGFloat(cos(a)), y: center.y + radius * CGFloat(sin(a)))
        }
    }
}
