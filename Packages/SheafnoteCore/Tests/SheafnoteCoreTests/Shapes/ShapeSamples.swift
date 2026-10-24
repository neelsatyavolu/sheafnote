import CoreGraphics
import Foundation
@testable import SheafnoteCore

/// Deterministic hand-drawn-looking strokes for the shape tests.
struct SeededNoise {
    private var state: UInt64
    init(seed: UInt64) { state = seed &* 6364136223846793005 &+ 1442695040888963407 }

    /// -1...1
    mutating func next() -> CGFloat {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return CGFloat(Double(state >> 33) / Double(1 << 31)) * 2 - 1
    }
}

enum ShapeSamples {
    static func jitter(_ points: [CGPoint], amount: CGFloat, seed: UInt64) -> [CGPoint] {
        var noise = SeededNoise(seed: seed)
        return points.map { CGPoint(x: $0.x + noise.next() * amount, y: $0.y + noise.next() * amount) }
    }

    static func polyline(_ corners: [CGPoint], step: CGFloat = 4) -> [CGPoint] {
        ShapeFigure.sample(polyline: corners, spacing: step)
    }

    static func line(from a: CGPoint, to b: CGPoint, noise: CGFloat = 0, seed: UInt64 = 1) -> [CGPoint] {
        jitter(polyline([a, b]), amount: noise, seed: seed)
    }

    /// Closed loop through `corners`, starting `startFraction` of the way round, overshooting by `overshoot` points.
    static func closed(_ corners: [CGPoint], startFraction: CGFloat = 0, overshoot: CGFloat = 0,
                       noise: CGFloat = 0, seed: UInt64 = 1) -> [CGPoint] {
        let ring = polyline(corners + [corners[0]])
        let start = Int(CGFloat(ring.count - 1) * startFraction)
        var path = Array(ring[start..<(ring.count - 1)]) + Array(ring[0...start])
        if overshoot > 0 {
            let extra = Int(overshoot / 4)
            path += Array(ring[(start + 1)..<min(start + 1 + extra, ring.count)])
        }
        return jitter(path, amount: noise, seed: seed)
    }

    static func rectangle(center: CGPoint = CGPoint(x: 200, y: 200), width: CGFloat = 160, height: CGFloat = 100,
                          rotation: Double = 0, startFraction: CGFloat = 0, noise: CGFloat = 0, seed: UInt64 = 1) -> [CGPoint] {
        closed(ShapeFigure.rectangleCorners(center: center, size: CGSize(width: width, height: height), rotation: rotation),
               startFraction: startFraction, noise: noise, seed: seed)
    }

    static func ellipse(center: CGPoint = CGPoint(x: 200, y: 200), rx: CGFloat = 80, ry: CGFloat = 80, rotation: Double = 0,
                        sweepDegrees: Double = 360, startDegrees: Double = 0, noise: CGFloat = 0, seed: UInt64 = 1) -> [CGPoint] {
        let count = max(8, Int(Double(max(rx, ry)) * 2 * .pi * sweepDegrees / 360 / 4))
        let c = CGFloat(cos(rotation)), s = CGFloat(sin(rotation))
        let pts = (0...count).map { i -> CGPoint in
            let a = (startDegrees + sweepDegrees * Double(i) / Double(count)) * .pi / 180
            let x = rx * CGFloat(cos(a)), y = ry * CGFloat(sin(a))
            return CGPoint(x: center.x + x * c - y * s, y: center.y + x * s + y * c)
        }
        return jitter(pts, amount: noise, seed: seed)
    }

    static func regularPolygon(sides: Int, radius: CGFloat = 90, center: CGPoint = CGPoint(x: 200, y: 200),
                               noise: CGFloat = 0, seed: UInt64 = 1) -> [CGPoint] {
        let corners = (0..<sides).map { i -> CGPoint in
            let a = -Double.pi / 2 + 2 * Double.pi * Double(i) / Double(sides)
            return CGPoint(x: center.x + radius * CGFloat(cos(a)), y: center.y + radius * CGFloat(sin(a)))
        }
        return closed(corners, noise: noise, seed: seed)
    }

    /// Shaft a->b then the head drawn in the same stroke.
    static func arrow(from a: CGPoint, to b: CGPoint, noise: CGFloat = 0, seed: UInt64 = 1) -> [CGPoint] {
        let (w1, w2) = ShapeFigure.arrowHead(from: a, to: b, lineWidth: 6)
        return jitter(polyline([a, b, w1, b, w2]), amount: noise, seed: seed)
    }

    static func scribble(seed: UInt64 = 7) -> [CGPoint] {
        var noise = SeededNoise(seed: seed)
        var corners: [CGPoint] = []
        for i in 0..<14 {
            corners.append(CGPoint(x: 100 + CGFloat(i % 2) * 80 + noise.next() * 20, y: 100 + CGFloat(i) * 9 + noise.next() * 6))
        }
        return polyline(corners)
    }

    static func randomWalk(seed: UInt64 = 3, count: Int = 80) -> [CGPoint] {
        var noise = SeededNoise(seed: seed)
        var p = CGPoint(x: 150, y: 150)
        return (0..<count).map { _ in
            p = CGPoint(x: p.x + noise.next() * 14, y: p.y + noise.next() * 14)
            return p
        }
    }
}
