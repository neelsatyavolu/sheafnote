import CoreGraphics
import Foundation

public enum PolygonMath {
    /// Even-odd point in polygon test.
    public static func contains(_ polygon: [CGPoint], _ p: CGPoint) -> Bool {
        guard polygon.count >= 3 else { return false }
        var inside = false
        var j = polygon.count - 1
        for i in 0..<polygon.count {
            let a = polygon[i], b = polygon[j]
            if (a.y > p.y) != (b.y > p.y), p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x { inside.toggle() }
            j = i
        }
        return inside
    }

    public static func segmentsIntersect(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ d: CGPoint) -> Bool {
        func cross(_ o: CGPoint, _ p: CGPoint, _ q: CGPoint) -> CGFloat {
            (p.x - o.x) * (q.y - o.y) - (p.y - o.y) * (q.x - o.x)
        }
        let d1 = cross(c, d, a), d2 = cross(c, d, b), d3 = cross(a, b, c), d4 = cross(a, b, d)
        return ((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) && ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0))
    }

    public static func bounds(of points: [CGPoint]) -> CGRect {
        guard let first = points.first else { return .null }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for p in points.dropFirst() {
            minX = min(minX, p.x); maxX = max(maxX, p.x); minY = min(minY, p.y); maxY = max(maxY, p.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// True when a freeform polygon and a convex quad (the oriented box) overlap.
    public static func overlaps(polygon: [CGPoint], convex quad: [CGPoint]) -> Bool {
        guard polygon.count >= 3, quad.count >= 3 else { return false }
        if quad.contains(where: { contains(polygon, $0) }) { return true }
        if polygon.contains(where: { contains(quad, $0) }) { return true }
        for i in 0..<polygon.count {
            let a = polygon[i], b = polygon[(i + 1) % polygon.count]
            for j in 0..<quad.count where segmentsIntersect(a, b, quad[j], quad[(j + 1) % quad.count]) { return true }
        }
        return false
    }
}
