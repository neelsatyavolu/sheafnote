import CoreGraphics
import Foundation
import Testing
@testable import SheafnoteCore

/// Sweeps sizes, positions, start points and jitter to make sure recognition does not hinge on one lucky sample.
@Suite struct ShapeRobustnessTests {
    static let seeds: [UInt64] = Array(1...12)

    @Test func circlesOfManySizes() {
        var misses: [String] = []
        for radius in [20.0, 35, 60, 100, 180] {
            for seed in Self.seeds {
                let noise = CGFloat(radius) * 0.03
                let stroke = ShapeSamples.ellipse(center: CGPoint(x: 300, y: 300), rx: CGFloat(radius), ry: CGFloat(radius),
                                                  startDegrees: Double(seed) * 29, noise: noise, seed: seed)
                if ShapeRecognizer.recognize(stroke)?.isCircle != true { misses.append("r\(radius)/s\(seed)") }
            }
        }
        #expect(misses.isEmpty, "missed circles: \(misses)")
    }

    @Test func rectanglesOfManyShapesAndStarts() {
        var misses: [String] = []
        for (w, h) in [(60.0, 40.0), (120, 80), (200, 200), (300, 90), (90, 300)] {
            for seed in Self.seeds {
                let stroke = ShapeSamples.rectangle(width: CGFloat(w), height: CGFloat(h), startFraction: CGFloat(seed) / 13,
                                                    noise: CGFloat(min(w, h)) * 0.03, seed: seed)
                guard case .rectangle(_, let size, _)? = ShapeRecognizer.recognize(stroke) else { misses.append("\(w)x\(h)/s\(seed)"); continue }
                let big = max(size.width, size.height), small = min(size.width, size.height)
                if abs(big - CGFloat(max(w, h))) > CGFloat(max(w, h)) * 0.12 || abs(small - CGFloat(min(w, h))) > CGFloat(min(w, h)) * 0.2 {
                    misses.append("size \(w)x\(h)/s\(seed)")
                }
            }
        }
        #expect(misses.isEmpty, "rectangle misses: \(misses)")
    }

    @Test func trianglesOfManyShapes() {
        let shapes: [[CGPoint]] = [
            [CGPoint(x: 200, y: 100), CGPoint(x: 300, y: 260), CGPoint(x: 100, y: 260)],
            [CGPoint(x: 100, y: 100), CGPoint(x: 300, y: 100), CGPoint(x: 100, y: 260)],
            [CGPoint(x: 100, y: 100), CGPoint(x: 330, y: 150), CGPoint(x: 160, y: 280)],
        ]
        var misses: [String] = []
        for (index, corners) in shapes.enumerated() {
            for seed in Self.seeds {
                let stroke = ShapeSamples.closed(corners, startFraction: CGFloat(seed) / 17, overshoot: CGFloat(seed % 3) * 10, noise: 2, seed: seed)
                if case .triangle? = ShapeRecognizer.recognize(stroke) { continue }
                misses.append("t\(index)/s\(seed)")
            }
        }
        #expect(misses.isEmpty, "triangle misses: \(misses)")
    }

    @Test func linesAtManyAngles() {
        var misses: [String] = []
        for degrees in stride(from: 0.0, to: 360, by: 15) {
            let a = degrees * .pi / 180
            let end = CGPoint(x: 300 + 160 * CGFloat(cos(a)), y: 300 + 160 * CGFloat(sin(a)))
            for seed in Self.seeds.prefix(4) {
                let stroke = ShapeSamples.line(from: CGPoint(x: 300, y: 300), to: end, noise: 2, seed: seed)
                if case .line? = ShapeRecognizer.recognize(stroke) { continue }
                misses.append("\(degrees)/s\(seed)")
            }
        }
        #expect(misses.isEmpty, "line misses: \(misses)")
    }

    @Test func arrowsAtManyAngles() {
        var misses: [String] = []
        for degrees in stride(from: 0.0, to: 360, by: 30) {
            let a = degrees * .pi / 180
            let end = CGPoint(x: 300 + 180 * CGFloat(cos(a)), y: 300 + 180 * CGFloat(sin(a)))
            for seed in Self.seeds.prefix(4) {
                if case .arrow? = ShapeRecognizer.recognize(ShapeSamples.arrow(from: CGPoint(x: 300, y: 300), to: end, noise: 1.5, seed: seed)) {
                    continue
                }
                misses.append("\(degrees)/s\(seed)")
            }
        }
        #expect(misses.isEmpty, "arrow misses: \(misses)")
    }

    @Test func arcsOfManySweeps() {
        var misses: [String] = []
        for sweep in [70.0, 110, 160, 220, 270] {
            for seed in Self.seeds.prefix(5) {
                let stroke = ShapeSamples.ellipse(center: CGPoint(x: 300, y: 300), rx: 90, ry: 90, sweepDegrees: sweep,
                                                  startDegrees: Double(seed) * 40, noise: 1.5, seed: seed)
                if case .arc? = ShapeRecognizer.recognize(stroke) { continue }
                misses.append("\(sweep)/s\(seed)")
            }
        }
        #expect(misses.isEmpty, "arc misses: \(misses)")
    }

    @Test func randomScribblesAreAlmostNeverShapes() {
        var accepted = 0
        for seed in UInt64(1)...60 {
            if ShapeRecognizer.recognize(ShapeSamples.randomWalk(seed: seed, count: 60 + Int(seed))) != nil { accepted += 1 }
            if ShapeRecognizer.recognize(ShapeSamples.scribble(seed: seed)) != nil { accepted += 1 }
        }
        #expect(accepted <= 6, "\(accepted) of 120 scribbles were taken for shapes")
    }

    @Test func recognitionIsFastOnLongStrokes() {
        let long = ShapeSamples.ellipse(rx: 400, ry: 400, noise: 4)
        let start = Date()
        for _ in 0..<50 { _ = ShapeRecognizer.recognize(long) }
        #expect(Date().timeIntervalSince(start) < 2)
    }
}
