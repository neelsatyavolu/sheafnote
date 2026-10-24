import CoreGraphics
import Foundation
import Testing
@testable import SheafnoteCore

@Suite struct ShapePlacementTests {
    func close(_ a: CGPoint, _ b: CGPoint, _ tolerance: CGFloat = 0.01) -> Bool { ShapeFit.distance(a, b) <= tolerance }

    func figures() -> [ShapeFigure] {
        [.line(from: CGPoint(x: 10, y: 20), to: CGPoint(x: 210, y: 90)),
         .arrow(from: CGPoint(x: 10, y: 20), to: CGPoint(x: 210, y: 90)),
         .rectangle(center: CGPoint(x: 100, y: 100), size: CGSize(width: 80, height: 40), rotation: 0.3),
         .ellipse(center: CGPoint(x: 100, y: 100), radii: CGSize(width: 60, height: 30), rotation: 0),
         .triangle([CGPoint(x: 50, y: 10), CGPoint(x: 90, y: 80), CGPoint(x: 10, y: 80)]),
         .polygon([CGPoint(x: 0, y: 0), CGPoint(x: 60, y: 0), CGPoint(x: 80, y: 40), CGPoint(x: 30, y: 70), CGPoint(x: -10, y: 40)]),
         .arc(center: CGPoint(x: 100, y: 100), radius: 50, startAngle: 0.5, sweep: 2.0)]
    }

    @Test func everyFigureSurvivesTheRoundTripThroughAnElement() throws {
        for figure in figures() {
            let placement = figure.placement(lineWidth: 3)
            let back = try #require(ShapeFigure(placement: placement), "\(figure)")
            #expect(back.kind == figure.kind)
            let a = figure.outline(spacing: 8), b = back.outline(spacing: 8)
            let sameBox = abs(figure.bounds.width - back.bounds.width) < 1 && abs(figure.bounds.height - back.bounds.height) < 1
            #expect(sameBox, "\(figure.kind) bounds changed")
            #expect(close(a.first ?? .zero, b.first ?? .zero, 0.5) || figure.kind == .ellipse, "\(figure.kind) start moved")
        }
    }

    @Test func arcKeepsItsGeometryAndDirection() throws {
        for sweep in [2.0, -2.0, 4.5] {
            let figure = ShapeFigure.arc(center: CGPoint(x: 100, y: 100), radius: 50, startAngle: 0.5, sweep: sweep)
            guard case .arc(let c, let r, let start, let back)? = ShapeFigure(placement: figure.placement()) else {
                Issue.record("arc lost"); continue
            }
            #expect(close(c, CGPoint(x: 100, y: 100), 0.01) && abs(r - 50) < 0.01 && abs(start - 0.5) < 0.001 && abs(back - sweep) < 0.001)
        }
    }

    @Test func linesGetASelectableFrame() {
        let flat = ShapeFigure.line(from: CGPoint(x: 0, y: 50), to: CGPoint(x: 200, y: 50)).placement()
        #expect(flat.frame.height >= ShapePlacement.minimumThickness && flat.frame.width == 200)
        #expect(flat.points == [CGPoint(x: 0, y: 0.5), CGPoint(x: 1, y: 0.5)])
    }

    @Test func arrowFrameContainsTheHead() {
        let arrow = ShapeFigure.arrow(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 200, y: 0))
        let placement = arrow.placement(lineWidth: 6)
        let (w1, w2) = ShapeFigure.arrowHead(from: .zero, to: CGPoint(x: 200, y: 0), lineWidth: 6)
        #expect(placement.frame.contains(w1) && placement.frame.contains(w2))
    }

    @Test func rotatingTheElementRotatesThePoints() throws {
        let placement = ShapePlacement(kind: .line, frame: CGRect(x: 0, y: 40, width: 100, height: 20), rotation: .pi / 2,
                                       points: [CGPoint(x: 0, y: 0.5), CGPoint(x: 1, y: 0.5)])
        guard case .line(let a, let b)? = ShapeFigure(placement: placement) else { Issue.record("no line"); return }
        #expect(close(a, CGPoint(x: 50, y: 0)) && close(b, CGPoint(x: 50, y: 100)))
    }

    @Test func damagedPlacementsAreRejected() {
        let frame = CGRect(x: 0, y: 0, width: 10, height: 10)
        #expect(ShapeFigure(placement: ShapePlacement(kind: .triangle, frame: frame, rotation: 0, points: [.zero])) == nil)
        #expect(ShapeFigure(placement: ShapePlacement(kind: .line, frame: frame, rotation: 0, points: [])) == nil)
        #expect(ShapeFigure(placement: ShapePlacement(kind: .rectangle, frame: .zero, rotation: 0, points: [])) == nil)
        let collinear = [CGPoint(x: 0, y: 0), CGPoint(x: 0.5, y: 0.5), CGPoint(x: 1, y: 1)]
        #expect(ShapeFigure(placement: ShapePlacement(kind: .arc, frame: frame, rotation: 0, points: collinear)) == nil)
    }
}

@Suite struct ShapeOutlineTests {
    @Test func closedOutlinesReturnToTheStart() {
        let figures: [ShapeFigure] = [
            .rectangle(center: .zero, size: CGSize(width: 40, height: 20), rotation: 0.2),
            .ellipse(center: .zero, radii: CGSize(width: 30, height: 10), rotation: 0.4),
            .triangle([CGPoint(x: 0, y: 0), CGPoint(x: 40, y: 0), CGPoint(x: 20, y: 30)]),
        ]
        for figure in figures {
            let outline = figure.outline()
            #expect(ShapeFit.distance(outline.first!, outline.last!) < 0.001, "\(figure.kind)")
            #expect(figure.isClosed)
        }
    }

    @Test func samplesAreNoFartherApartThanTheSpacing() {
        let outline = ShapeFigure.rectangle(center: .zero, size: CGSize(width: 100, height: 60), rotation: 0).outline(spacing: 3)
        let gaps = zip(outline, outline.dropFirst()).map { ShapeFit.distance($0, $1) }
        #expect((gaps.max() ?? 0) <= 3.001)
    }

    @Test func arrowOutlineIncludesTheHead() {
        let arrow = ShapeFigure.arrow(from: .zero, to: CGPoint(x: 100, y: 0))
        let line = ShapeFigure.line(from: .zero, to: CGPoint(x: 100, y: 0))
        #expect(arrow.bounds.height > line.bounds.height)
        #expect(arrow.polylines().count == 2 && line.polylines().count == 1)
    }

    @Test func circleDetection() {
        #expect(ShapeFigure.ellipse(center: .zero, radii: CGSize(width: 20, height: 20), rotation: 0).isCircle)
        #expect(!ShapeFigure.ellipse(center: .zero, radii: CGSize(width: 20, height: 10), rotation: 0).isCircle)
        #expect(!ShapeFigure.line(from: .zero, to: CGPoint(x: 1, y: 1)).isCircle)
    }

    @Test func arcOutlineStaysOnTheCircle() {
        let arc = ShapeFigure.arc(center: CGPoint(x: 50, y: 50), radius: 40, startAngle: 0, sweep: 1.5)
        for p in arc.outline(spacing: 4) { #expect(abs(ShapeFit.distance(p, CGPoint(x: 50, y: 50)) - 40) < 0.001) }
    }
}

@Suite struct ShapeBuilderTests {
    @Test func cornerToCornerKinds() {
        let drag = [CGPoint(x: 200, y: 300), CGPoint(x: 120, y: 180)]
        guard case .rectangle(let c, let size, _)? = ShapeBuilder.figure(kind: .rectangle, path: drag) else { Issue.record("no rect"); return }
        #expect(c == CGPoint(x: 160, y: 240) && size == CGSize(width: 80, height: 120))
        guard case .ellipse(_, let r, _)? = ShapeBuilder.figure(kind: .ellipse, path: drag) else { Issue.record("no ellipse"); return }
        #expect(r == CGSize(width: 40, height: 60))
        guard case .triangle(let t)? = ShapeBuilder.figure(kind: .triangle, path: drag) else { Issue.record("no triangle"); return }
        #expect(t[0] == CGPoint(x: 160, y: 180) && t.count == 3)
        guard case .polygon(let h)? = ShapeBuilder.figure(kind: .polygon, path: drag) else { Issue.record("no polygon"); return }
        #expect(h.count == 6)
    }

    @Test func nearlyEqualEllipseRadiiMakeACircle() {
        #expect(ShapeBuilder.figure(kind: .ellipse, path: [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 104)])?.isCircle == true)
    }

    @Test func linesAndArrowsSnapToTheAxes() {
        guard case .line(let a, let b)? = ShapeBuilder.figure(kind: .line, path: [CGPoint(x: 0, y: 0), CGPoint(x: 200, y: 5)]) else {
            Issue.record("no line"); return
        }
        #expect(a.y == b.y)
        #expect(ShapeBuilder.figure(kind: .arrow, path: [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 100)])?.kind == .arrow)
    }

    @Test func arcBulgesTowardsTheFarthestPoint() throws {
        let path = ShapeSamples.ellipse(rx: 80, ry: 80, sweepDegrees: 120, startDegrees: 210)
        guard case .arc(_, let r, _, _)? = ShapeBuilder.figure(kind: .arc, path: path) else { Issue.record("no arc"); return }
        #expect(abs(r - 80) < 4)
    }

    @Test func dragsTooShortOrFlatMakeNothing() {
        #expect(ShapeBuilder.figure(kind: .rectangle, path: [CGPoint(x: 0, y: 0), CGPoint(x: 5, y: 5)]) == nil)
        #expect(ShapeBuilder.figure(kind: .rectangle, path: [CGPoint(x: 0, y: 0), CGPoint(x: 200, y: 2)]) == nil)
        #expect(ShapeBuilder.figure(kind: .line, path: []) == nil)
        #expect(ShapeBuilder.figure(kind: .arc, path: [CGPoint(x: 0, y: 0), CGPoint(x: 50, y: 0), CGPoint(x: 100, y: 0)]) == nil)
    }

    @Test func settingsRoundTripAndModesMapToKinds() {
        let settings = ShapeToolSettings(mode: .arrow, strokeHex: "#FF0000", fillHex: "#00FF00", lineWidth: 6)
        #expect(JSONCoding.decode(ShapeToolSettings.self, from: JSONCoding.encode(settings)) == settings)
        #expect(ShapeMode.auto.kind == nil && ShapeMode.polygon.kind == .polygon)
        for kind in ShapeKind.allCases { #expect(ShapeMode(rawValue: kind.rawValue)?.kind == kind) }
    }
}

@Suite struct StraightLineFitTests {
    @Test func firstToLastPoint() throws {
        let line = try #require(StraightLineFit.line(from: [CGPoint(x: 0, y: 0), CGPoint(x: 50, y: 20), CGPoint(x: 100, y: 100)]))
        #expect(line.0 == CGPoint(x: 0, y: 0) && line.1 == CGPoint(x: 100, y: 100))
    }

    @Test func wobblyHorizontalAndVerticalStrokesSnapToTheAxis() throws {
        let horizontal = try #require(StraightLineFit.line(from: [CGPoint(x: 0, y: 100), CGPoint(x: 200, y: 108)]))
        #expect(horizontal.0.y == horizontal.1.y)
        let vertical = try #require(StraightLineFit.line(from: [CGPoint(x: 100, y: 0), CGPoint(x: 95, y: 200)]))
        #expect(abs(vertical.0.x - vertical.1.x) < 0.0001)
        #expect(abs(ShapeFit.distance(vertical.0, vertical.1) - hypot(5, 200)) < 0.01)
    }

    @Test func reversedHorizontalStrokeKeepsItsDirection() throws {
        let line = try #require(StraightLineFit.line(from: [CGPoint(x: 200, y: 100), CGPoint(x: 0, y: 103)]))
        #expect(line.0.x > line.1.x)
    }

    @Test func dotsAndEmptyInputAreNotLines() {
        #expect(StraightLineFit.line(from: []) == nil)
        #expect(StraightLineFit.line(from: [CGPoint(x: 5, y: 5)]) == nil)
        #expect(StraightLineFit.line(from: [CGPoint(x: 5, y: 5), CGPoint(x: 8, y: 6)]) == nil)
    }

    @Test func steepAnglesAreLeftAlone() throws {
        let line = try #require(StraightLineFit.line(from: [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 40)]))
        #expect(line.1 == CGPoint(x: 100, y: 40))
    }
}

@Suite struct ShapeElementTests {
    let page = UUID()

    func element(_ figure: ShapeFigure, fill: String? = nil, width: Double = 3) -> ElementValue {
        ShapeElementGeometry.element(for: figure, pageID: page, zIndex: 4, strokeHex: "#112233", fillHex: fill, lineWidth: width)
    }

    @Test func elementCarriesPayloadAndGeometry() throws {
        let e = element(.rectangle(center: CGPoint(x: 100, y: 100), size: CGSize(width: 60, height: 40), rotation: 0), fill: "#FFFF00")
        #expect(e.kind == .shape && e.pageID == page && e.zIndex == 4)
        #expect(e.frame == CGRect(x: 70, y: 80, width: 60, height: 40))
        let payload = try #require(PayloadCodec.decode(ShapePayload.self, from: e.payload))
        #expect(payload.shapeKind == .rectangle && payload.strokeHex == "#112233" && payload.fillHex == "#FFFF00")
    }

    @Test func openShapesNeverCarryAFill() throws {
        let e = element(.line(from: .zero, to: CGPoint(x: 100, y: 0)), fill: "#FFFF00")
        #expect(try #require(PayloadCodec.decode(ShapePayload.self, from: e.payload)).fillHex == nil)
    }

    @Test func figureOfElementRebuildsPageGeometry() throws {
        let original = ShapeFigure.triangle([CGPoint(x: 50, y: 10), CGPoint(x: 90, y: 80), CGPoint(x: 10, y: 80)])
        guard case .triangle(let v)? = ShapeElementGeometry.figure(of: element(original)) else { Issue.record("no triangle"); return }
        for (a, b) in zip(v, [CGPoint(x: 50, y: 10), CGPoint(x: 90, y: 80), CGPoint(x: 10, y: 80)]) { #expect(ShapeFit.distance(a, b) < 0.01) }
        guard case .triangle(let local)? = ShapeElementGeometry.localFigure(of: element(original)) else { Issue.record("no local"); return }
        #expect(PolygonMath.bounds(of: local).origin == .zero || abs(PolygonMath.bounds(of: local).minX) < 0.01)
    }

    @Test func restyleChangesOnlyWhatIsAskedFor() throws {
        let e = element(.rectangle(center: .zero, size: CGSize(width: 40, height: 40), rotation: 0), fill: "#FFFF00", width: 3)
        let recolored = ShapeElementGeometry.restyled(e, strokeHex: "#FF0000")
        let payload = try #require(PayloadCodec.decode(ShapePayload.self, from: recolored.payload))
        #expect(payload.strokeHex == "#FF0000" && payload.lineWidth == 3 && payload.fillHex == "#FFFF00")
        #expect(recolored.id == e.id && recolored.frame == e.frame)
        let thicker = try #require(PayloadCodec.decode(ShapePayload.self, from: ShapeElementGeometry.restyled(e, lineWidth: 9).payload))
        #expect(thicker.lineWidth == 9 && thicker.strokeHex == "#112233")
        let text = ElementValue(pageID: page, kind: .text, frame: .zero)
        #expect(ShapeElementGeometry.restyled(text, strokeHex: "#FF0000") == text)
        let broken = ElementValue(pageID: page, kind: .shape, frame: .zero, payload: Data([1]))
        #expect(ShapeElementGeometry.restyled(broken, strokeHex: "#FF0000") == broken)
    }

    @Test func refillSetsAndClearsTheFillOfClosedShapesOnly() throws {
        let box = element(.rectangle(center: .zero, size: CGSize(width: 40, height: 40), rotation: 0))
        let filled = ShapeElementGeometry.refilled(box, fillHex: "#00FF00")
        #expect(try #require(PayloadCodec.decode(ShapePayload.self, from: filled.payload)).fillHex == "#00FF00")
        let cleared = ShapeElementGeometry.refilled(filled, fillHex: nil)
        #expect(try #require(PayloadCodec.decode(ShapePayload.self, from: cleared.payload)).fillHex == nil)
        let line = element(.line(from: .zero, to: CGPoint(x: 50, y: 0)))
        let attempt = ShapeElementGeometry.refilled(line, fillHex: "#00FF00")
        #expect(try #require(PayloadCodec.decode(ShapePayload.self, from: attempt.payload)).fillHex == nil)
        let broken = ElementValue(pageID: page, kind: .shape, frame: .zero, payload: Data([1]))
        #expect(ShapeElementGeometry.refilled(broken, fillHex: "#00FF00") == broken)
    }

    @Test func foreignAndBrokenPayloadsGiveNoFigure() {
        let text = ElementValue(pageID: page, kind: .text, frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        #expect(ShapeElementGeometry.figure(of: text) == nil)
        let broken = ElementValue(pageID: page, kind: .shape, frame: CGRect(x: 0, y: 0, width: 10, height: 10), payload: Data([1, 2]))
        #expect(ShapeElementGeometry.figure(of: broken) == nil && ShapeElementGeometry.localFigure(of: broken) == nil)
    }

    // MARK: Hit testing

    @Test func diagonalLineIgnoresTheEmptyCornerOfItsFrame() {
        let e = element(.line(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 200, y: 200)))
        let tester = ShapeHitTester(element: e)
        let emptyCorner: [CGPoint] = [CGPoint(x: 150, y: 10), CGPoint(x: 190, y: 10), CGPoint(x: 190, y: 50), CGPoint(x: 150, y: 50)]
        let crossing: [CGPoint] = [CGPoint(x: 90, y: 90), CGPoint(x: 110, y: 90), CGPoint(x: 110, y: 110), CGPoint(x: 90, y: 110)]
        #expect(!tester.intersects(polygon: emptyCorner))
        #expect(tester.intersects(polygon: crossing))
        #expect(tester.contains(point: CGPoint(x: 100, y: 104)))
        #expect(!tester.contains(point: CGPoint(x: 180, y: 20)))
    }

    @Test func lassoAroundTheWholeShapeSelectsIt() {
        let e = element(.ellipse(center: CGPoint(x: 100, y: 100), radii: CGSize(width: 40, height: 40), rotation: 0))
        let around: [CGPoint] = [CGPoint(x: 0, y: 0), CGPoint(x: 200, y: 0), CGPoint(x: 200, y: 200), CGPoint(x: 0, y: 200)]
        #expect(ShapeHitTester(element: e).intersects(polygon: around))
    }

    @Test func filledShapeIsHitInsideButHollowIsNot() {
        let figure = ShapeFigure.rectangle(center: CGPoint(x: 100, y: 100), size: CGSize(width: 120, height: 120), rotation: 0)
        let tinyInside: [CGPoint] = [CGPoint(x: 95, y: 95), CGPoint(x: 105, y: 95), CGPoint(x: 100, y: 105)]
        #expect(ShapeHitTester(element: element(figure, fill: "#00FF00")).intersects(polygon: tinyInside))
        #expect(ShapeHitTester(element: element(figure, fill: "#00FF00")).contains(point: CGPoint(x: 100, y: 100)))
        #expect(!ShapeHitTester(element: element(figure)).intersects(polygon: tinyInside))
        #expect(!ShapeHitTester(element: element(figure)).contains(point: CGPoint(x: 100, y: 100)))
        #expect(ShapeHitTester(element: element(figure)).contains(point: CGPoint(x: 40, y: 100)))
    }

    @Test func rotatedShapeIsHitWhereItIsDrawn() {
        var e = element(.line(from: CGPoint(x: 0, y: 50), to: CGPoint(x: 200, y: 50)))
        e.rotation = .pi / 2
        let tester = ShapeHitTester(element: e)
        #expect(tester.contains(point: CGPoint(x: 100, y: 0)) || tester.contains(point: CGPoint(x: 100, y: 20)))
        #expect(!tester.contains(point: CGPoint(x: 20, y: 50)))
    }

    @Test func transformMovesTheElementFrame() {
        let e = element(.rectangle(center: CGPoint(x: 100, y: 100), size: CGSize(width: 60, height: 40), rotation: 0))
        let moved = ShapeHitTester(element: e).transformed(by: CGAffineTransform(translationX: 30, y: -10))
        #expect(moved.frame == e.frame.offsetBy(dx: 30, dy: -10) && moved.id == e.id)
        #expect(ShapeHitTester(element: e).bounds == e.frame)
    }

    @Test func brokenPayloadFallsBackToTheBox() {
        let broken = ElementValue(pageID: page, kind: .shape, frame: CGRect(x: 0, y: 0, width: 100, height: 100), payload: Data([9]))
        let tester = ShapeHitTester(element: broken)
        #expect(tester.contains(point: CGPoint(x: 50, y: 50)))
        #expect(tester.intersects(polygon: [CGPoint(x: 40, y: 40), CGPoint(x: 60, y: 40), CGPoint(x: 50, y: 60)]))
    }
}
