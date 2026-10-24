import CoreGraphics
import Foundation
import Testing
@testable import SheafnoteCore

@Suite struct ShapeRecognizerTests {
    func near(_ a: CGFloat, _ b: CGFloat, _ tolerance: CGFloat) -> Bool { abs(a - b) <= tolerance }

    // MARK: Lines

    @Test func straightStrokeBecomesALine() throws {
        let stroke = ShapeSamples.line(from: CGPoint(x: 50, y: 60), to: CGPoint(x: 250, y: 140), noise: 1.5)
        guard case .line(let a, let b)? = ShapeRecognizer.recognize(stroke) else { Issue.record("not a line"); return }
        #expect(near(a.x, 50, 3) && near(a.y, 60, 3) && near(b.x, 250, 3) && near(b.y, 140, 3))
    }

    @Test func nearlyHorizontalLineSnapsToHorizontal() throws {
        let stroke = ShapeSamples.line(from: CGPoint(x: 50, y: 100), to: CGPoint(x: 250, y: 108))
        guard case .line(let a, let b)? = ShapeRecognizer.recognize(stroke) else { Issue.record("not a line"); return }
        #expect(a.y == b.y)
        #expect(near(ShapeFit.distance(a, b), ShapeFit.distance(stroke.first!, stroke.last!), 0.01))
    }

    @Test func diagonalLineKeepsItsAngle() throws {
        let stroke = ShapeSamples.line(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 200, y: 100))
        guard case .line(let a, let b)? = ShapeRecognizer.recognize(stroke) else { Issue.record("not a line"); return }
        #expect(near(b.y - a.y, 100, 0.01))
    }

    // MARK: Arrows

    @Test func shaftWithHeadBecomesAnArrow() throws {
        let stroke = ShapeSamples.arrow(from: CGPoint(x: 40, y: 200), to: CGPoint(x: 260, y: 120), noise: 1)
        guard case .arrow(let from, let to)? = ShapeRecognizer.recognize(stroke) else { Issue.record("not an arrow"); return }
        #expect(ShapeFit.distance(from, CGPoint(x: 40, y: 200)) < 6)
        #expect(ShapeFit.distance(to, CGPoint(x: 260, y: 120)) < 6)
    }

    @Test func arrowDrawnHeadFirstPointsAtTheTip() throws {
        let forward = ShapeSamples.arrow(from: CGPoint(x: 40, y: 200), to: CGPoint(x: 260, y: 200))
        guard case .arrow(_, let to)? = ShapeRecognizer.recognize(Array(forward.reversed())) else {
            Issue.record("not an arrow"); return
        }
        #expect(ShapeFit.distance(to, CGPoint(x: 260, y: 200)) < 6)
    }

    // MARK: Closed shapes

    @Test func circleBecomesACircle() throws {
        let stroke = ShapeSamples.ellipse(rx: 70, ry: 70, noise: 2)
        let figure = try #require(ShapeRecognizer.recognize(stroke))
        #expect(figure.isCircle)
        guard case .ellipse(let c, let r, _) = figure else { return }
        #expect(near(r.width, 70, 6) && ShapeFit.distance(c, CGPoint(x: 200, y: 200)) < 6)
    }

    @Test func wideEllipseKeepsItsRadii() throws {
        guard case .ellipse(_, let r, let rotation)? = ShapeRecognizer.recognize(ShapeSamples.ellipse(rx: 110, ry: 50, noise: 1.5)) else {
            Issue.record("not an ellipse"); return
        }
        #expect(near(r.width, 110, 8) && near(r.height, 50, 6) && rotation == 0)
    }

    @Test func tiltedEllipseKeepsItsTilt() throws {
        guard case .ellipse(_, _, let rotation)? = ShapeRecognizer.recognize(ShapeSamples.ellipse(rx: 110, ry: 45, rotation: 0.6)) else {
            Issue.record("not an ellipse"); return
        }
        #expect(near(CGFloat(rotation), 0.6, 0.08))
    }

    @Test func circleDrawnWithOverlapIsStillACircle() throws {
        var stroke = ShapeSamples.ellipse(rx: 70, ry: 70, noise: 1)
        stroke += Array(stroke.prefix(10))
        #expect(try #require(ShapeRecognizer.recognize(stroke)).isCircle)
    }

    @Test func rectangleBecomesARectangle() throws {
        let stroke = ShapeSamples.rectangle(width: 180, height: 110, noise: 2)
        guard case .rectangle(let c, let size, let rotation)? = ShapeRecognizer.recognize(stroke) else {
            Issue.record("not a rectangle"); return
        }
        #expect(near(size.width, 180, 10) && near(size.height, 110, 10))
        #expect(rotation == 0 && ShapeFit.distance(c, CGPoint(x: 200, y: 200)) < 8)
    }

    @Test func rectangleStartedMidEdgeWithOvershootIsStillARectangle() throws {
        let corners = ShapeFigure.rectangleCorners(center: CGPoint(x: 200, y: 200), size: CGSize(width: 150, height: 100), rotation: 0)
        let stroke = ShapeSamples.closed(corners, startFraction: 0.37, overshoot: 24, noise: 1.5)
        guard case .rectangle(_, let size, _)? = ShapeRecognizer.recognize(stroke) else { Issue.record("not a rectangle"); return }
        #expect(near(size.width, 150, 10) && near(size.height, 100, 10))
    }

    @Test func rotatedRectangleKeepsItsRotation() throws {
        let stroke = ShapeSamples.rectangle(width: 200, height: 90, rotation: 0.5, noise: 1)
        guard case .rectangle(_, let size, let rotation)? = ShapeRecognizer.recognize(stroke) else {
            Issue.record("not a rectangle"); return
        }
        #expect(near(CGFloat(rotation), 0.5, 0.06) && near(size.width, 200, 10) && near(size.height, 90, 10))
    }

    @Test func nearlySquareBecomesASquare() throws {
        guard case .rectangle(_, let size, _)? = ShapeRecognizer.recognize(ShapeSamples.rectangle(width: 120, height: 124, noise: 1)) else {
            Issue.record("not a rectangle"); return
        }
        #expect(size.width == size.height)
    }

    @Test func triangleBecomesATriangle() throws {
        let corners = [CGPoint(x: 200, y: 100), CGPoint(x: 290, y: 260), CGPoint(x: 110, y: 260)]
        guard case .triangle(let v)? = ShapeRecognizer.recognize(ShapeSamples.closed(corners, noise: 2)) else {
            Issue.record("not a triangle"); return
        }
        for corner in corners { #expect(v.contains { ShapeFit.distance($0, corner) < 14 }) }
    }

    @Test func pentagonAndHexagonBecomePolygons() throws {
        for sides in [5, 6] {
            let figure = ShapeRecognizer.recognize(ShapeSamples.regularPolygon(sides: sides, noise: 1.5))
            guard case .polygon(let v)? = figure else { Issue.record("\(sides) sides not a polygon: \(String(describing: figure))"); continue }
            #expect(v.count == sides)
        }
    }

    @Test func irregularQuadrilateralIsAPolygon() throws {
        let corners = [CGPoint(x: 140, y: 100), CGPoint(x: 260, y: 100), CGPoint(x: 340, y: 240), CGPoint(x: 60, y: 240)]
        guard case .polygon(let v)? = ShapeRecognizer.recognize(ShapeSamples.closed(corners, noise: 1)) else {
            Issue.record("not a polygon"); return
        }
        #expect(v.count == 4)
    }

    // MARK: Arcs

    @Test func openCurveBecomesAnArc() throws {
        let stroke = ShapeSamples.ellipse(rx: 100, ry: 100, sweepDegrees: 150, startDegrees: 200, noise: 1.2)
        guard case .arc(let c, let r, _, let sweep)? = ShapeRecognizer.recognize(stroke) else { Issue.record("not an arc"); return }
        #expect(near(r, 100, 8) && ShapeFit.distance(c, CGPoint(x: 200, y: 200)) < 8)
        #expect(near(CGFloat(abs(sweep)), 150 * .pi / 180, 0.15))
    }

    @Test func arcDrawnTheOtherWayHasANegativeSweep() throws {
        let stroke = ShapeSamples.ellipse(rx: 100, ry: 100, sweepDegrees: -140, startDegrees: 340)
        guard case .arc(_, _, _, let sweep)? = ShapeRecognizer.recognize(stroke) else { Issue.record("not an arc"); return }
        #expect(sweep < 0)
    }

    @Test func largeOpenCIsAnArc() throws {
        let stroke = ShapeSamples.ellipse(rx: 90, ry: 90, sweepDegrees: 280, startDegrees: 40, noise: 1)
        guard case .arc? = ShapeRecognizer.recognize(stroke) else { Issue.record("not an arc"); return }
    }

    // MARK: Rejections

    @Test func scribblesAreNotShapes() {
        #expect(ShapeRecognizer.recognize(ShapeSamples.scribble()) == nil)
        #expect(ShapeRecognizer.recognize(ShapeSamples.scribble(seed: 21)) == nil)
        #expect(ShapeRecognizer.recognize(ShapeSamples.randomWalk()) == nil)
        #expect(ShapeRecognizer.recognize(ShapeSamples.randomWalk(seed: 11, count: 120)) == nil)
    }

    @Test func tinyAndEmptyInputIsRejected() {
        #expect(ShapeRecognizer.recognize([]) == nil)
        #expect(ShapeRecognizer.recognize([CGPoint(x: 1, y: 1)]) == nil)
        #expect(ShapeRecognizer.recognize(ShapeSamples.ellipse(rx: 3, ry: 3)) == nil)
        #expect(ShapeRecognizer.recognize(ShapeSamples.line(from: .zero, to: CGPoint(x: 10, y: 0))) == nil)
    }

    @Test func aZigzagIsNotAnArrowOrArc() {
        let zigzag = ShapeSamples.polyline([CGPoint(x: 0, y: 0), CGPoint(x: 60, y: 50), CGPoint(x: 120, y: 0),
                                            CGPoint(x: 180, y: 50), CGPoint(x: 240, y: 0)])
        #expect(ShapeRecognizer.recognize(zigzag) == nil)
    }

    @Test func handwrittenLetterIsNotAShape() {
        // An "S": two opposite bends do not fit one circle.
        let top = ShapeSamples.ellipse(center: CGPoint(x: 100, y: 80), rx: 40, ry: 40, sweepDegrees: 220, startDegrees: -30)
        let bottom = ShapeSamples.ellipse(center: CGPoint(x: 100, y: 160), rx: 40, ry: 40, sweepDegrees: -220, startDegrees: -150)
        #expect(ShapeRecognizer.recognize(top + bottom) == nil)
    }

    @Test func noisyInputStaysRecognized() throws {
        for seed in UInt64(1)...6 {
            #expect(try #require(ShapeRecognizer.recognize(ShapeSamples.ellipse(rx: 75, ry: 75, noise: 3, seed: seed))).isCircle)
            guard case .rectangle? = ShapeRecognizer.recognize(ShapeSamples.rectangle(noise: 3, seed: seed)) else {
                Issue.record("rectangle lost at seed \(seed)"); continue
            }
        }
    }
}
