import CoreGraphics
import Foundation
import Testing
@testable import SheafnoteCore

@Suite struct LassoGeometryTests {
    let square: [CGPoint] = [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0), CGPoint(x: 100, y: 100), CGPoint(x: 0, y: 100)]

    @Test func dragAroundAnAreaBecomesAClosedPolygon() throws {
        let drag = ShapeSamples.closed(square, noise: 0.4)
        let polygon = try #require(LassoGeometry.closedPolygon(from: drag))
        #expect(polygon.count >= 4 && polygon.count < drag.count)
        #expect(abs(LassoGeometry.area(of: polygon) - 10_000) < 600)
    }

    @Test func tapsAndTinyLoopsAreNotLassos() {
        #expect(LassoGeometry.closedPolygon(from: []) == nil)
        #expect(LassoGeometry.closedPolygon(from: [CGPoint(x: 5, y: 5), CGPoint(x: 8, y: 6)]) == nil)
        #expect(LassoGeometry.isTap([CGPoint(x: 5, y: 5), CGPoint(x: 9, y: 7)]))
        let tiny = ShapeSamples.closed([.zero, CGPoint(x: 12, y: 0), CGPoint(x: 12, y: 12), CGPoint(x: 0, y: 12)])
        #expect(LassoGeometry.closedPolygon(from: tiny) == nil)
    }

    @Test func aStraightDragEnclosesNothing() {
        #expect(LassoGeometry.closedPolygon(from: ShapeSamples.line(from: .zero, to: CGPoint(x: 200, y: 0))) == nil)
    }

    @Test func longPathsAreThinnedForCheapHitTests() throws {
        let drag = ShapeSamples.ellipse(rx: 300, ry: 300, noise: 2)
        let polygon = try #require(LassoGeometry.closedPolygon(from: drag))
        #expect(polygon.count <= 240)
    }

    @Test func polylineInsideOrCrossingTheLassoIsHit() {
        #expect(LassoGeometry.polyline([CGPoint(x: 40, y: 40), CGPoint(x: 60, y: 60)], intersects: square))
        #expect(LassoGeometry.polyline([CGPoint(x: -50, y: 50), CGPoint(x: 150, y: 50)], intersects: square))
        #expect(!LassoGeometry.polyline([CGPoint(x: 200, y: 200), CGPoint(x: 300, y: 250)], intersects: square))
        #expect(!LassoGeometry.polyline([], intersects: square))
        #expect(!LassoGeometry.polyline([CGPoint(x: 50, y: 50)], intersects: [.zero]))
    }

    @Test func unionSkipsNullRects() {
        let union = LassoGeometry.union([CGRect(x: 0, y: 0, width: 10, height: 10), .null, CGRect(x: 20, y: 20, width: 5, height: 5)])
        #expect(union == CGRect(x: 0, y: 0, width: 25, height: 25))
        #expect(LassoGeometry.union([]) == nil)
        #expect(LassoGeometry.union([.null]) == nil)
    }

    @Test func tapReachShrinksWhenZoomedIn() {
        #expect(LassoGeometry.tapReach(zoom: 4) < LassoGeometry.tapReach(zoom: 1))
        #expect(LassoGeometry.tapReach(zoom: 0.01).isFinite)
    }
}

@Suite struct LassoFilterTests {
    @Test func eachFilterAcceptsItsKinds() {
        #expect(LassoFilters.handwriting.accepts(.shape) && !LassoFilters.handwriting.accepts(.image))
        #expect(LassoFilters.images.accepts(.image) && LassoFilters.images.accepts(.sticker) && LassoFilters.images.accepts(.tape))
        #expect(LassoFilters.text.accepts(.text) && LassoFilters.text.accepts(.link) && !LassoFilters.text.accepts(.shape))
        for kind in ElementKind.allCases { #expect(LassoFilters.all.accepts(kind)) }
        for kind in ElementKind.allCases { #expect(!LassoFilters([]).accepts(kind)) }
    }

    @Test func filtersRoundTripThroughJSON() {
        let filters: LassoFilters = [.handwriting, .text]
        #expect(JSONCoding.decode(LassoFilters.self, from: JSONCoding.encode(filters)) == filters)
    }
}

@Suite struct SelectionClipboardTests {
    func element(zIndex: Int, at x: CGFloat) -> ElementValue {
        ElementValue(pageID: UUID(), kind: .text, frame: CGRect(x: x, y: 10, width: 50, height: 20), zIndex: zIndex)
    }

    @Test func roundTrips() throws {
        let clip = SelectionClipboard(strokes: Data([1, 2, 3]), elements: [element(zIndex: 1, at: 5)],
                                      bounds: CGRect(x: 1, y: 2, width: 30, height: 40), sourcePageID: UUID())
        #expect(SelectionClipboard.decode(clip.encoded()) == clip)
    }

    @Test func rejectsForeignDamagedAndNewerData() {
        #expect(SelectionClipboard.decode(Data("not json".utf8)) == nil)
        #expect(SelectionClipboard.decode(Data()) == nil)
        let empty = SelectionClipboard(strokes: Data(), elements: [], bounds: .zero, sourcePageID: nil)
        #expect(SelectionClipboard.decode(empty.encoded()) == nil)
        var newer = SelectionClipboard(strokes: Data([1]), elements: [], bounds: .zero, sourcePageID: nil)
        newer.version = SelectionClipboard.currentVersion + 1
        #expect(SelectionClipboard.decode(newer.encoded()) == nil)
    }

    @Test func elementCopiesGetNewIdsPageAndStacking() {
        let a = element(zIndex: 3, at: 0), b = element(zIndex: 1, at: 100)
        let clip = SelectionClipboard(strokes: Data(), elements: [a, b], bounds: .zero, sourcePageID: nil)
        let target = UUID()
        let copies = clip.elementCopies(for: target, offset: CGSize(width: 24, height: 24), topZIndex: 7)
        #expect(copies.count == 2)
        #expect(copies.allSatisfy { $0.pageID == target && $0.id != a.id && $0.id != b.id })
        #expect(copies.map(\.zIndex) == [8, 9])
        #expect(copies[0].frame.origin == CGPoint(x: 124, y: 34))   // b (lower z) comes first
        #expect(copies[1].frame.origin == CGPoint(x: 24, y: 34))
    }
}

@Suite struct PastePlacementTests {
    let page = CGSize(width: 600, height: 800)
    let bounds = CGRect(x: 100, y: 100, width: 200, height: 100)

    @Test func samePageStepsAwayFromTheOriginal() {
        let id = UUID()
        let first = PastePlacement.offset(for: bounds, sourcePageID: id, targetPageID: id, targetSize: page, earlierPastes: 0)
        let second = PastePlacement.offset(for: bounds, sourcePageID: id, targetPageID: id, targetSize: page, earlierPastes: 1)
        #expect(first == CGSize(width: 24, height: 24) && second == CGSize(width: 48, height: 48))
    }

    @Test func otherPageKeepsThePosition() {
        #expect(PastePlacement.offset(for: bounds, sourcePageID: UUID(), targetPageID: UUID(), targetSize: page, earlierPastes: 0) == .zero)
    }

    @Test func contentIsPulledBackInsideTheTargetPage() {
        let small = CGSize(width: 250, height: 150)
        let offset = PastePlacement.offset(for: bounds, sourcePageID: nil, targetPageID: UUID(), targetSize: small, earlierPastes: 0)
        let moved = bounds.offsetBy(dx: offset.width, dy: offset.height)
        #expect(moved.maxX <= 250 && moved.maxY <= 150 && moved.minX >= 0 && moved.minY >= 0)
    }

    @Test func contentLargerThanThePagePinsToTheTopLeft() {
        let huge = CGRect(x: 50, y: 60, width: 900, height: 900)
        let offset = PastePlacement.offset(for: huge, sourcePageID: nil, targetPageID: UUID(), targetSize: page, earlierPastes: 0)
        #expect(huge.offsetBy(dx: offset.width, dy: offset.height).origin == .zero)
    }

    @Test func pasteAtThePageEdgeNeverLandsOnTheOriginal() {
        let id = UUID()
        let corner = CGRect(x: 400, y: 600, width: 200, height: 200)
        let offset = PastePlacement.offset(for: corner, sourcePageID: id, targetPageID: id, targetSize: page, earlierPastes: 0)
        #expect(offset != .zero)
        let moved = corner.offsetBy(dx: offset.width, dy: offset.height)
        #expect(moved.minX >= 0 && moved.minY >= 0 && moved.maxX <= 600 && moved.maxY <= 800)
    }
}

@Suite struct HandwritingTextLayoutTests {
    let page = CGSize(width: 600, height: 800)

    @Test func fontFollowsTheHeightOfOneLine() {
        let one = HandwritingTextLayout.layout(text: "hello", over: CGRect(x: 40, y: 40, width: 120, height: 40), pageSize: page)
        let three = HandwritingTextLayout.layout(text: "a\nb\nc", over: CGRect(x: 40, y: 40, width: 120, height: 120), pageSize: page)
        #expect(one.fontSize == 40 * 0.62)
        #expect(three.fontSize == 40 * 0.62)
        #expect(three.frame.height > one.frame.height)
    }

    @Test func fontIsClamped() {
        let tiny = HandwritingTextLayout.layout(text: "x", over: CGRect(x: 0, y: 0, width: 5, height: 4), pageSize: page)
        let huge = HandwritingTextLayout.layout(text: "x", over: CGRect(x: 0, y: 0, width: 500, height: 500), pageSize: page)
        #expect(tiny.fontSize == HandwritingTextLayout.minimumFontSize && huge.fontSize == HandwritingTextLayout.maximumFontSize)
    }

    @Test func frameStaysOnThePage() {
        let result = HandwritingTextLayout.layout(text: String(repeating: "word ", count: 30),
                                                  over: CGRect(x: 550, y: 780, width: 40, height: 20), pageSize: page)
        #expect(result.frame.minX >= 0 && result.frame.maxX <= page.width + 0.01)
        #expect(result.frame.minY >= 0 && result.frame.maxY <= page.height + 28)
    }
}
