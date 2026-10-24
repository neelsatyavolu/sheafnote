import CoreGraphics
import Foundation

/// Small numeric helpers shared by the shape recognizer: resampling, simplification and circle fitting.
enum ShapeFit {
    static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }

    static func pathLength(_ points: [CGPoint]) -> CGFloat {
        zip(points, points.dropFirst()).reduce(0) { $0 + distance($1.0, $1.1) }
    }

    /// Drops points closer than `minDistance` to their predecessor (the last point is always kept).
    static func dedupe(_ points: [CGPoint], minDistance: CGFloat) -> [CGPoint] {
        guard var last = points.first else { return [] }
        var out = [last]
        for p in points.dropFirst() where distance(p, last) >= minDistance {
            out.append(p)
            last = p
        }
        if let end = points.last, out.last != end {
            if out.count > 1, distance(out[out.count - 1], end) < minDistance { out[out.count - 1] = end } else { out.append(end) }
        }
        return out
    }

    /// `count` points evenly spaced along the path.
    static func resample(_ points: [CGPoint], count: Int) -> [CGPoint] {
        guard points.count > 1, count > 1 else { return points }
        let total = pathLength(points)
        guard total > 0 else { return points }
        let step = total / CGFloat(count - 1)
        var out = [points[0]]
        var carried: CGFloat = 0
        var previous = points[0]
        for next in points.dropFirst() {
            var segment = distance(previous, next)
            guard segment > 0 else { continue }
            var from = previous
            while carried + segment >= step, out.count < count {
                let t = (step - carried) / segment
                let p = CGPoint(x: from.x + (next.x - from.x) * t, y: from.y + (next.y - from.y) * t)
                out.append(p)
                from = p
                segment = distance(from, next)
                carried = 0
            }
            carried += segment
            previous = next
        }
        if out.count < count, let last = points.last { out.append(last) }
        return out
    }

    static func distanceToSegment(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return distance(p, a) }
        let t = min(max(((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared, 0), 1)
        return distance(p, CGPoint(x: a.x + dx * t, y: a.y + dy * t))
    }

    static func distanceToPolyline(_ p: CGPoint, _ line: [CGPoint], closed: Bool) -> CGFloat {
        guard line.count > 1 else { return line.first.map { distance(p, $0) } ?? .infinity }
        var best = CGFloat.infinity
        for i in 0..<(line.count - 1) { best = min(best, distanceToSegment(p, line[i], line[i + 1])) }
        if closed, let first = line.first, let last = line.last { best = min(best, distanceToSegment(p, last, first)) }
        return best
    }

    /// Ramer-Douglas-Peucker simplification of an open path.
    static func rdp(_ points: [CGPoint], epsilon: CGFloat) -> [CGPoint] {
        guard points.count > 2, let first = points.first, let last = points.last else { return points }
        var worst: CGFloat = 0, index = 0
        for i in 1..<(points.count - 1) {
            let d = distanceToSegment(points[i], first, last)
            if d > worst { worst = d; index = i }
        }
        guard worst > epsilon else { return [first, last] }
        let left = rdp(Array(points[0...index]), epsilon: epsilon)
        let right = rdp(Array(points[index...]), epsilon: epsilon)
        return Array(left.dropLast()) + right
    }

    /// Algebraic (Kasa) least-squares circle through the points.
    static func fitCircle(_ points: [CGPoint]) -> (center: CGPoint, radius: CGFloat)? {
        guard points.count >= 3 else { return nil }
        let n = CGFloat(points.count)
        let mx = points.reduce(0) { $0 + $1.x } / n, my = points.reduce(0) { $0 + $1.y } / n
        var suu: CGFloat = 0, svv: CGFloat = 0, suv: CGFloat = 0, suuu: CGFloat = 0, svvv: CGFloat = 0
        var suvv: CGFloat = 0, svuu: CGFloat = 0
        for p in points {
            let u = p.x - mx, v = p.y - my
            suu += u * u; svv += v * v; suv += u * v
            suuu += u * u * u; svvv += v * v * v; suvv += u * v * v; svuu += v * u * u
        }
        let det = suu * svv - suv * suv
        guard abs(det) > 1e-9 else { return nil }
        let rhsU = (suuu + suvv) / 2, rhsV = (svvv + svuu) / 2
        let uc = (rhsU * svv - rhsV * suv) / det
        let vc = (rhsV * suu - rhsU * suv) / det
        let radius = sqrt(uc * uc + vc * vc + (suu + svv) / n)
        guard radius.isFinite, radius > 0 else { return nil }
        return (CGPoint(x: mx + uc, y: my + vc), radius)
    }

    /// Smallest absolute difference of two angles, 0...pi.
    static func angleGap(_ a: Double, _ b: Double) -> Double {
        var d = (a - b).truncatingRemainder(dividingBy: 2 * .pi)
        if d > .pi { d -= 2 * .pi }
        if d < -.pi { d += 2 * .pi }
        return abs(d)
    }

    static func angle(from a: CGPoint, to b: CGPoint) -> Double { atan2(Double(b.y - a.y), Double(b.x - a.x)) }

    /// Angle at `b` between segments b->a and b->c, 0...pi.
    static func interiorAngle(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> Double {
        angleGap(angle(from: b, to: a), angle(from: b, to: c))
    }

    static func polygonArea(_ p: [CGPoint]) -> CGFloat {
        guard p.count >= 3 else { return 0 }
        var sum: CGFloat = 0
        for i in p.indices {
            let a = p[i], b = p[(i + 1) % p.count]
            sum += a.x * b.y - b.x * a.y
        }
        return abs(sum) / 2
    }
}
