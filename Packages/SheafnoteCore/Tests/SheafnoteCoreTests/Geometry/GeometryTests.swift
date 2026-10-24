import CoreGraphics
import Foundation
import Testing
@testable import SheafnoteCore

@Suite struct GeometryTests {
    func element(_ frame: CGRect, rotation: Double = 0) -> ElementValue {
        ElementValue(pageID: UUID(), kind: .image, frame: frame, rotation: rotation)
    }

    let square: [CGPoint] = [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0), CGPoint(x: 100, y: 100), CGPoint(x: 0, y: 100)]

    @Test func pointInPolygon() {
        #expect(PolygonMath.contains(square, CGPoint(x: 50, y: 50)))
        #expect(!PolygonMath.contains(square, CGPoint(x: 150, y: 50)))
        #expect(!PolygonMath.contains([CGPoint.zero], .zero))
    }

    @Test func concavePolygon() {
        let c: [CGPoint] = [.init(x: 0, y: 0), .init(x: 100, y: 0), .init(x: 100, y: 100), .init(x: 50, y: 20), .init(x: 0, y: 100)]
        #expect(!PolygonMath.contains(c, CGPoint(x: 50, y: 80)))
        #expect(PolygonMath.contains(c, CGPoint(x: 10, y: 10)))
    }

    @Test func segmentIntersection() {
        #expect(PolygonMath.segmentsIntersect(.init(x: 0, y: 0), .init(x: 10, y: 10), .init(x: 0, y: 10), .init(x: 10, y: 0)))
        #expect(!PolygonMath.segmentsIntersect(.init(x: 0, y: 0), .init(x: 1, y: 1), .init(x: 5, y: 5), .init(x: 6, y: 5)))
    }

    @Test func boundsOfPoints() {
        #expect(PolygonMath.bounds(of: square) == CGRect(x: 0, y: 0, width: 100, height: 100))
        #expect(PolygonMath.bounds(of: []).isNull)
    }

    @Test func unrotatedBoundsAndContains() {
        let t = OrientedBoxHitTester(element: element(CGRect(x: 10, y: 20, width: 100, height: 50)))
        #expect(t.bounds == CGRect(x: 10, y: 20, width: 100, height: 50))
        #expect(t.contains(point: CGPoint(x: 60, y: 45)))
        #expect(!t.contains(point: CGPoint(x: 5, y: 45)))
    }

    @Test func rotatedNinetyDegrees() {
        let t = OrientedBoxHitTester(element: element(CGRect(x: 0, y: 0, width: 100, height: 20), rotation: .pi / 2))
        let b = t.bounds
        #expect(abs(b.width - 20) < 0.001 && abs(b.height - 100) < 0.001)
        #expect(t.contains(point: CGPoint(x: 50, y: 40)))      // inside along vertical after rotation
        #expect(!t.contains(point: CGPoint(x: 90, y: 10)))     // inside the unrotated frame only
    }

    @Test func lassoOverlapCases() {
        let t = OrientedBoxHitTester(element: element(CGRect(x: 40, y: 40, width: 20, height: 20)))
        #expect(t.intersects(polygon: square))                                           // lasso contains box
        let small: [CGPoint] = [.init(x: 45, y: 45), .init(x: 55, y: 45), .init(x: 50, y: 55)]
        #expect(t.intersects(polygon: small))                                            // box contains lasso
        let crossing: [CGPoint] = [.init(x: 50, y: 50), .init(x: 120, y: 50), .init(x: 120, y: 120), .init(x: 50, y: 120)]
        #expect(t.intersects(polygon: crossing))                                         // partial overlap
        let away: [CGPoint] = [.init(x: 200, y: 200), .init(x: 220, y: 200), .init(x: 210, y: 220)]
        #expect(!t.intersects(polygon: away))
        #expect(!t.intersects(polygon: [.zero]))
    }

    @Test func lassoCrossingEdgeOnlyOverlap() {
        let t = OrientedBoxHitTester(element: element(CGRect(x: 0, y: 0, width: 100, height: 10)))
        let thin: [CGPoint] = [.init(x: 50, y: -20), .init(x: 55, y: -20), .init(x: 55, y: 30), .init(x: 50, y: 30)]
        #expect(t.intersects(polygon: thin))
    }

    @Test func translateTransform() {
        let t = OrientedBoxHitTester(element: element(CGRect(x: 0, y: 0, width: 100, height: 50)))
        let moved = t.transformed(by: CGAffineTransform(translationX: 30, y: 10))
        #expect(moved.frame == CGRect(x: 30, y: 10, width: 100, height: 50))
        #expect(moved.rotation == 0)
    }

    @Test func scaleAndRotateTransform() {
        let t = OrientedBoxHitTester(element: element(CGRect(x: 0, y: 0, width: 100, height: 50)))
        let scaled = t.transformed(by: CGAffineTransform(scaleX: 2, y: 2))
        #expect(scaled.frame.size == CGSize(width: 200, height: 100))
        #expect(scaled.frame.midX == 100 && scaled.frame.midY == 50)   // scaled about the origin moves the centre
        let rotated = t.transformed(by: CGAffineTransform(rotationAngle: .pi / 4))
        #expect(abs(rotated.rotation - .pi / 4) < 0.0001)
        #expect(abs(rotated.frame.width - 100) < 0.001)
    }

    @Test func transformKeepsIdentity() {
        let e = element(CGRect(x: 1, y: 2, width: 3, height: 4))
        let moved = OrientedBoxHitTester(element: e).transformed(by: .identity)
        #expect(moved.id == e.id && moved.pageID == e.pageID && moved.kind == e.kind)
    }
}
