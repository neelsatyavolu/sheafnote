import CoreGraphics
import Foundation

/// Turns a hand-drawn stroke (page coordinates) into a clean geometric figure, or nil when it is not a shape
/// (a scribble, handwriting, a path too short to mean anything). A geometric fit only; nothing is learned.
public enum ShapeRecognizer {
    /// Ends closer than this fraction of the path length count as a closed loop.
    static let closureRatio: CGFloat = 0.15
    static let minimumLength: CGFloat = 24
    static let minimumExtent: CGFloat = 16
    /// A closed path much longer than its bounding box diagonal is a scribble, not an outline.
    static let maximumLoopRatio: CGFloat = 5.5

    public static func recognize(_ raw: [CGPoint]) -> ShapeFigure? {
        let points = ShapeFit.dedupe(raw, minDistance: 0.75)
        guard points.count >= 4, let first = points.first, let last = points.last else { return nil }
        let length = ShapeFit.pathLength(points)
        let box = PolygonMath.bounds(of: points)
        let diagonal = hypot(box.width, box.height)
        guard length >= minimumLength, diagonal >= minimumExtent else { return nil }

        let closed = ShapeFit.distance(first, last) <= closureRatio * length
        if closed {
            guard length <= maximumLoopRatio * diagonal else { return nil }
            return ClosedShapeFit.figure(points: points, diagonal: diagonal)
        }
        return lineFigure(points, length: length)
            ?? ArrowFit.figure(points: points, diagonal: diagonal)
            ?? ArcFit.figure(points: points, length: length)
    }

    // MARK: Line

    private static func lineFigure(_ points: [CGPoint], length: CGFloat) -> ShapeFigure? {
        guard let a = points.first, let b = points.last else { return nil }
        let chord = ShapeFit.distance(a, b)
        guard chord >= minimumLength, length <= chord * 1.3 else { return nil }
        let deviation = points.map { ShapeFit.distanceToSegment($0, a, b) }.max() ?? 0
        guard deviation <= max(3, 0.06 * chord) else { return nil }
        let snapped = StraightLineFit.snapped(from: a, to: b)
        return .line(from: snapped.0, to: snapped.1)
    }
}

// MARK: Arrow

enum ArrowFit {
    /// A shaft with the head drawn in the same stroke: shaft A->B, wing B->C, back to the tip, wing B->D.
    /// The reverse order (head first, then the shaft back) is accepted too.
    static func figure(points: [CGPoint], diagonal: CGFloat) -> ShapeFigure? {
        let simplified = ShapeFit.rdp(points, epsilon: max(3, 0.03 * diagonal))
        guard simplified.count == 5 else { return nil }
        return match(simplified) ?? match(Array(simplified.reversed()))
    }

    private static func match(_ v: [CGPoint]) -> ShapeFigure? {
        let (a, b, c, b2, d) = (v[0], v[1], v[2], v[3], v[4])
        let shaft = ShapeFit.distance(a, b)
        guard shaft >= 30, ShapeFit.distance(b, b2) <= 0.3 * shaft else { return nil }
        let back = ShapeFit.angle(from: b, to: a)
        guard let sideC = wingSide(tip: b, end: c, back: back, shaft: shaft),
              let sideD = wingSide(tip: b2, end: d, back: back, shaft: shaft), sideC != sideD else { return nil }
        return .arrow(from: a, to: b)
    }

    /// +1 / -1 for the side of the shaft a wing is on, nil when the wing is too short, long or flat.
    private static func wingSide(tip: CGPoint, end: CGPoint, back: Double, shaft: CGFloat) -> Int? {
        let length = ShapeFit.distance(tip, end)
        guard length >= 0.08 * shaft, length <= 0.6 * shaft else { return nil }
        let angle = ShapeFit.angle(from: tip, to: end)
        let gap = ShapeFit.angleGap(angle, back)
        guard gap >= 12 * .pi / 180, gap <= 75 * .pi / 180 else { return nil }
        var signed = angle - back
        while signed > .pi { signed -= 2 * .pi }
        while signed < -.pi { signed += 2 * .pi }
        return signed > 0 ? 1 : -1
    }
}

// MARK: Arc

enum ArcFit {
    static func figure(points: [CGPoint], length: CGFloat) -> ShapeFigure? {
        let sample = ShapeFit.resample(points, count: 48)
        guard let circle = ShapeFit.fitCircle(sample), let first = points.first else { return nil }
        let residuals = sample.map { abs(ShapeFit.distance($0, circle.center) - circle.radius) / circle.radius }
        let mean = residuals.reduce(0, +) / CGFloat(residuals.count)
        guard mean <= 0.05, (residuals.max() ?? 1) <= 0.14 else { return nil }
        let sweep = totalSweep(sample, around: circle.center)
        guard abs(sweep) >= 0.6, abs(sweep) <= 2 * .pi * 0.95 else { return nil }
        return .arc(center: circle.center, radius: circle.radius,
                    startAngle: ShapeFit.angle(from: circle.center, to: first), sweep: sweep)
    }

    /// Signed angle travelled around `center`, with wrap-around removed.
    static func totalSweep(_ points: [CGPoint], around center: CGPoint) -> Double {
        var total = 0.0
        var previous = ShapeFit.angle(from: center, to: points[0])
        for p in points.dropFirst() {
            let now = ShapeFit.angle(from: center, to: p)
            var step = now - previous
            while step > .pi { step -= 2 * .pi }
            while step < -.pi { step += 2 * .pi }
            total += step
            previous = now
        }
        return total
    }
}
