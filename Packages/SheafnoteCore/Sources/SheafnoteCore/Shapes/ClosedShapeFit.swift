import CoreGraphics
import Foundation

/// Classifies a closed stroke as ellipse/circle, rectangle, triangle or polygon by comparing how well each fits.
enum ClosedShapeFit {
    static func figure(points: [CGPoint], diagonal: CGFloat) -> ShapeFigure? {
        let eps = max(2.5, 0.045 * diagonal)
        let sample = ShapeFit.resample(points, count: 72)
        let corners = cornerVertices(of: points, epsilon: eps)
        let ellipse = EllipseFit(sample: sample, scale: diagonal / 2)
        let polygonError = corners.count >= 3 ? meanError(sample, corners, scale: diagonal / 2) : .infinity
        let polygonOK = (3...12).contains(corners.count) && polygonError <= 0.07 && edgesAreSolid(corners)

        if let ellipse, ellipse.error <= 0.07 {
            let beatsPolygon = !polygonOK
                || (corners.count >= 5 ? ellipse.error <= polygonError + 0.004 : ellipse.error < polygonError * 0.6)
            if beatsPolygon { return ellipse.figure }
        }
        guard polygonOK else { return nil }
        switch corners.count {
        case 3: return isTriangle(corners) ? .triangle(corners) : nil
        case 4: return rectangle(from: corners) ?? .polygon(corners)
        default: return .polygon(corners)
        }
    }

    // MARK: Corners

    /// Corner points of a closed stroke: simplified, closing duplicate dropped, straight-through vertices removed.
    static func cornerVertices(of points: [CGPoint], epsilon: CGFloat) -> [CGPoint] {
        var v = ShapeFit.rdp(points, epsilon: epsilon)
        if v.count > 3 { mergeEnds(&v, epsilon: epsilon) }
        let straight = 150.0 * .pi / 180
        while v.count > 3, let flat = flattest(v), flat.angle > straight { v.remove(at: flat.index) }
        var merged = true
        while merged, v.count > 3 {
            merged = false
            for i in v.indices {
                let j = (i + 1) % v.count
                if ShapeFit.distance(v[i], v[j]) < 3 * epsilon {
                    v[i] = CGPoint(x: (v[i].x + v[j].x) / 2, y: (v[i].y + v[j].y) / 2)
                    v.remove(at: j)
                    merged = true
                    break
                }
            }
        }
        return v
    }

    /// The stroke's first and last vertex sit at the same spot when the loop was closed near a corner: make them one
    /// vertex, placed where the two edges they belong to meet.
    private static func mergeEnds(_ v: inout [CGPoint], epsilon: CGFloat) {
        let n = v.count
        let (a, b) = (v[0], v[n - 1])
        let reach = max(3 * epsilon, 0.35 * min(ShapeFit.distance(a, v[1]), ShapeFit.distance(b, v[n - 2])))
        let gap = ShapeFit.distance(a, b)
        guard gap < reach else { return }
        let middle = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        v[0] = lineIntersection(v[1], a, v[n - 2], b).flatMap { ShapeFit.distance($0, middle) <= 2 * gap + epsilon ? $0 : nil } ?? middle
        v.removeLast()
    }

    /// Where the line through p1,p2 meets the line through p3,p4; nil when they are nearly parallel.
    private static func lineIntersection(_ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint, _ p4: CGPoint) -> CGPoint? {
        let d1 = CGPoint(x: p2.x - p1.x, y: p2.y - p1.y), d2 = CGPoint(x: p4.x - p3.x, y: p4.y - p3.y)
        let cross = d1.x * d2.y - d1.y * d2.x
        guard abs(cross) > 0.2 * hypot(d1.x, d1.y) * hypot(d2.x, d2.y) else { return nil }
        let t = ((p3.x - p1.x) * d2.y - (p3.y - p1.y) * d2.x) / cross
        return CGPoint(x: p1.x + t * d1.x, y: p1.y + t * d1.y)
    }

    private static func flattest(_ v: [CGPoint]) -> (index: Int, angle: Double)? {
        v.indices.map { i in
            (i, ShapeFit.interiorAngle(v[(i + v.count - 1) % v.count], v[i], v[(i + 1) % v.count]))
        }.max { $0.1 < $1.1 }.map { (index: $0.0, angle: $0.1) }
    }

    static func meanError(_ sample: [CGPoint], _ polygon: [CGPoint], scale: CGFloat) -> CGFloat {
        let total = sample.reduce(0) { $0 + ShapeFit.distanceToPolyline($1, polygon, closed: true) }
        return total / CGFloat(sample.count) / max(scale, 1)
    }

    /// No edge is a sliver compared with the perimeter.
    private static func edgesAreSolid(_ v: [CGPoint]) -> Bool {
        let lengths = v.indices.map { ShapeFit.distance(v[$0], v[($0 + 1) % v.count]) }
        let perimeter = lengths.reduce(0, +)
        return perimeter > 0 && lengths.allSatisfy { $0 >= 0.06 * perimeter }
    }

    private static func isTriangle(_ v: [CGPoint]) -> Bool {
        let minimum = 12.0 * .pi / 180
        return v.indices.allSatisfy { ShapeFit.interiorAngle(v[($0 + 2) % 3], v[$0], v[($0 + 1) % 3]) >= minimum }
    }

    // MARK: Rectangle

    static func rectangle(from q: [CGPoint]) -> ShapeFigure? {
        guard q.count == 4 else { return nil }
        let right = Double.pi / 2, tolerance = 20.0 * .pi / 180
        for i in 0..<4 {
            let angle = ShapeFit.interiorAngle(q[(i + 3) % 4], q[i], q[(i + 1) % 4])
            if abs(angle - right) > tolerance { return nil }
        }
        let sides = (0..<4).map { ShapeFit.distance(q[$0], q[($0 + 1) % 4]) }
        guard ratioOK(sides[0], sides[2]), ratioOK(sides[1], sides[3]) else { return nil }

        let direction = averageDirection(ShapeFit.angle(from: q[0], to: q[1]), ShapeFit.angle(from: q[3], to: q[2]))
        var rotation = direction
        while rotation > .pi / 4 { rotation -= .pi / 2 }
        while rotation <= -.pi / 4 { rotation += .pi / 2 }
        if abs(rotation) < 6 * .pi / 180 { rotation = 0 }
        return box(of: q, rotation: rotation)
    }

    private static func ratioOK(_ a: CGFloat, _ b: CGFloat) -> Bool { min(a, b) > 0 && max(a, b) / min(a, b) <= 1.4 }

    private static func averageDirection(_ a: Double, _ b: Double) -> Double {
        atan2(sin(a) + sin(b), cos(a) + cos(b))
    }

    private static func box(of q: [CGPoint], rotation: Double) -> ShapeFigure {
        let c = CGFloat(cos(rotation)), s = CGFloat(sin(rotation))
        let us = q.map { $0.x * c + $0.y * s }, vs = q.map { -$0.x * s + $0.y * c }
        let (u0, u1, v0, v1) = (us.min() ?? 0, us.max() ?? 0, vs.min() ?? 0, vs.max() ?? 0)
        var width = u1 - u0, height = v1 - v0
        if abs(width - height) <= 0.08 * max(width, height) {
            let side = (width + height) / 2
            width = side; height = side
        }
        let cu = (u0 + u1) / 2, cv = (v0 + v1) / 2
        let center = CGPoint(x: cu * c - cv * s, y: cu * s + cv * c)
        return .rectangle(center: center, size: CGSize(width: width, height: height), rotation: rotation)
    }
}

/// Principal-axis ellipse fit of a closed sample.
struct EllipseFit {
    let center: CGPoint
    let radii: CGSize
    let rotation: Double
    /// Mean radial deviation, relative to half the bounding diagonal.
    let error: CGFloat

    init?(sample: [CGPoint], scale: CGFloat) {
        guard sample.count >= 8 else { return nil }
        let n = CGFloat(sample.count)
        let mx = sample.reduce(0) { $0 + $1.x } / n, my = sample.reduce(0) { $0 + $1.y } / n
        var sxx: CGFloat = 0, syy: CGFloat = 0, sxy: CGFloat = 0
        for p in sample {
            let dx = p.x - mx, dy = p.y - my
            sxx += dx * dx; syy += dy * dy; sxy += dx * dy
        }
        let phi = 0.5 * atan2(2 * Double(sxy), Double(sxx - syy))
        let c = CGFloat(cos(phi)), s = CGFloat(sin(phi))
        let us = sample.map { ($0.x - mx) * c + ($0.y - my) * s }
        let vs = sample.map { -($0.x - mx) * s + ($0.y - my) * c }
        let (u0, u1, v0, v1) = (us.min() ?? 0, us.max() ?? 0, vs.min() ?? 0, vs.max() ?? 0)
        let a = (u1 - u0) / 2, b = (v1 - v0) / 2
        guard a > 1, b > 1 else { return nil }
        let cu = (u0 + u1) / 2, cv = (v0 + v1) / 2
        var deviation: CGFloat = 0
        for (u, v) in zip(us, vs) {
            let rho = hypot((u - cu) / a, (v - cv) / b)
            deviation += abs(rho - 1)
        }
        error = deviation / n * ((a + b) / 2) / max(scale, 1)
        center = CGPoint(x: mx + cu * c - cv * s, y: my + cu * s + cv * c)
        let (r, rot) = Self.canonical(a: a, b: b, phi: phi)
        radii = r
        rotation = rot
    }

    /// Circles lose their rotation, near-axis ellipses snap to the axes.
    private static func canonical(a: CGFloat, b: CGFloat, phi: Double) -> (CGSize, Double) {
        if abs(a - b) <= 0.1 * max(a, b) {
            let r = (a + b) / 2
            return (CGSize(width: r, height: r), 0)
        }
        var rotation = phi, ra = a, rb = b
        while rotation > .pi / 2 { rotation -= .pi }
        while rotation <= -.pi / 2 { rotation += .pi }
        let snap = 7.0 * .pi / 180
        if abs(rotation) < snap { return (CGSize(width: ra, height: rb), 0) }
        if abs(abs(rotation) - .pi / 2) < snap { swap(&ra, &rb); return (CGSize(width: ra, height: rb), 0) }
        return (CGSize(width: ra, height: rb), rotation)
    }

    var figure: ShapeFigure { .ellipse(center: center, radii: radii, rotation: rotation) }
}
