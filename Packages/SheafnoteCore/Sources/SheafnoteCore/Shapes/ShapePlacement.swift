import CoreGraphics
import Foundation

/// How a figure is stored on a shape element: the element frame and rotation, plus defining points in the frame's
/// unit square (origin top-left). Rectangle and ellipse need no points.
public struct ShapePlacement: Equatable, Sendable {
    public var kind: ShapeKind
    public var frame: CGRect
    public var rotation: Double
    public var points: [CGPoint]

    public init(kind: ShapeKind, frame: CGRect, rotation: Double, points: [CGPoint]) {
        self.kind = kind; self.frame = frame; self.rotation = rotation; self.points = points
    }

    /// Frames never get thinner than this, so a horizontal line still has a selectable box.
    public static let minimumThickness: CGFloat = 12
}

public extension ShapeFigure {
    /// The element geometry for this figure. `lineWidth` pads the frame so arrow heads stay inside it.
    func placement(lineWidth: CGFloat = 3) -> ShapePlacement {
        switch self {
        case .rectangle(let c, let s, let r):
            return ShapePlacement(kind: .rectangle, frame: Self.frame(center: c, size: s), rotation: r, points: [])
        case .ellipse(let c, let radii, let r):
            let size = CGSize(width: radii.width * 2, height: radii.height * 2)
            return ShapePlacement(kind: .ellipse, frame: Self.frame(center: c, size: size), rotation: r, points: [])
        case .line(let a, let b):
            return Self.pointPlacement(.line, [a, b], extra: [])
        case .arrow(let a, let b):
            let (w1, w2) = Self.arrowHead(from: a, to: b, lineWidth: lineWidth)
            return Self.pointPlacement(.arrow, [a, b], extra: [w1, w2])
        case .triangle(let p):
            return Self.pointPlacement(.triangle, p, extra: [])
        case .polygon(let p):
            return Self.pointPlacement(.polygon, p, extra: [])
        case .arc(let c, let radius, let start, let sweep):
            let at: (Double) -> CGPoint = { CGPoint(x: c.x + radius * CGFloat(cos($0)), y: c.y + radius * CGFloat(sin($0))) }
            let defining = [at(start), at(start + sweep / 2), at(start + sweep)]
            return Self.pointPlacement(.arc, defining, extra: Self.arcPoints(center: c, radius: radius, start: start, sweep: sweep, spacing: 12))
        }
    }

    /// Rebuilds the figure in the coordinate space of `frame` (rotation about its centre is applied to the figure).
    /// Returns nil when the points do not fit the kind.
    init?(placement p: ShapePlacement) {
        let f = p.frame
        guard f.width.isFinite, f.height.isFinite, f.width > 0, f.height > 0 else { return nil }
        let center = CGPoint(x: f.midX, y: f.midY)
        let absolute: [CGPoint] = p.points.map { u in
            Self.rotate(CGPoint(x: f.minX + u.x * f.width, y: f.minY + u.y * f.height), about: center, by: p.rotation)
        }
        switch p.kind {
        case .rectangle: self = .rectangle(center: center, size: f.size, rotation: p.rotation)
        case .ellipse: self = .ellipse(center: center, radii: CGSize(width: f.width / 2, height: f.height / 2), rotation: p.rotation)
        case .line:
            guard absolute.count >= 2 else { return nil }
            self = .line(from: absolute[0], to: absolute[1])
        case .arrow:
            guard absolute.count >= 2 else { return nil }
            self = .arrow(from: absolute[0], to: absolute[1])
        case .triangle:
            guard absolute.count == 3 else { return nil }
            self = .triangle(absolute)
        case .polygon:
            guard absolute.count >= 3 else { return nil }
            self = .polygon(absolute)
        case .arc:
            guard absolute.count >= 3, let arc = Self.circle(through: absolute[0], absolute[1], absolute[2]) else { return nil }
            self = .arc(center: arc.center, radius: arc.radius, startAngle: arc.start, sweep: arc.sweep)
        }
    }

    // MARK: Helpers

    internal static func rotate(_ p: CGPoint, about c: CGPoint, by angle: Double) -> CGPoint {
        guard angle != 0 else { return p }
        let cs = CGFloat(cos(angle)), sn = CGFloat(sin(angle))
        let dx = p.x - c.x, dy = p.y - c.y
        return CGPoint(x: c.x + dx * cs - dy * sn, y: c.y + dx * sn + dy * cs)
    }

    private static func frame(center: CGPoint, size: CGSize) -> CGRect {
        CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
    }

    /// Frame around `defining` (and `extra` points that must stay inside), at least `minimumThickness` thick.
    private static func pointPlacement(_ kind: ShapeKind, _ defining: [CGPoint], extra: [CGPoint]) -> ShapePlacement {
        var box = PolygonMath.bounds(of: defining + extra)
        let minimum = ShapePlacement.minimumThickness
        if box.width < minimum { box = box.insetBy(dx: (box.width - minimum) / 2, dy: 0) }
        if box.height < minimum { box = box.insetBy(dx: 0, dy: (box.height - minimum) / 2) }
        let unit = defining.map { CGPoint(x: ($0.x - box.minX) / box.width, y: ($0.y - box.minY) / box.height) }
        return ShapePlacement(kind: kind, frame: box, rotation: 0, points: unit)
    }

    /// Circle through three points, with the arc that runs from `a` through `b` to `c`.
    internal static func circle(through a: CGPoint, _ b: CGPoint, _ c: CGPoint)
        -> (center: CGPoint, radius: CGFloat, start: Double, sweep: Double)? {
        let d = 2 * (a.x * (b.y - c.y) + b.x * (c.y - a.y) + c.x * (a.y - b.y))
        guard abs(d) > 1e-6 else { return nil }
        let a2 = a.x * a.x + a.y * a.y, b2 = b.x * b.x + b.y * b.y, c2 = c.x * c.x + c.y * c.y
        let ux = (a2 * (b.y - c.y) + b2 * (c.y - a.y) + c2 * (a.y - b.y)) / d
        let uy = (a2 * (c.x - b.x) + b2 * (a.x - c.x) + c2 * (b.x - a.x)) / d
        let center = CGPoint(x: ux, y: uy)
        let radius = ShapeFit.distance(center, a)
        guard radius.isFinite, radius > 0 else { return nil }
        let start = ShapeFit.angle(from: center, to: a)
        let mid = ShapeFit.angle(from: center, to: b)
        let end = ShapeFit.angle(from: center, to: c)
        func normalized(_ x: Double) -> Double {
            var v = x.truncatingRemainder(dividingBy: 2 * .pi)
            if v < 0 { v += 2 * .pi }
            return v
        }
        let toMid = normalized(mid - start), toEnd = normalized(end - start)
        // Positive direction when the middle point comes before the end going clockwise; otherwise go the other way.
        let sweep = toMid <= toEnd ? toEnd : toEnd - 2 * .pi
        return (center, radius, start, sweep)
    }
}
