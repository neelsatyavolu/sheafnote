import PencilKit
import UIKit
import SheafnoteCore

/// `PageInkAccess` over a `PageSession`: reads strokes with stable ids and applies undoable edits.
@MainActor
final class PageInk: PageInkAccess {
    private unowned let page: PageSession

    init(page: PageSession) { self.page = page }

    var strokes: [IdentifiedStroke] {
        zip(page.strokeIDs, page.drawing.strokes).map { IdentifiedStroke(id: $0, stroke: $1) }
    }

    var lastInkTouchDate: Date? { page.lastInkTouchDate }

    func edit(_ name: LocalizedStringResource, _ body: (inout [PKStroke]) -> Void) {
        var list = page.drawing.strokes
        body(&list)
        page.setDrawing(PKDrawing(strokes: list), undoName: String(localized: name))
    }

    /// Same as `edit`, but also tells the caller the new ids of the strokes at `indices` (a transform changes ids).
    func edit(_ name: LocalizedStringResource, indices: Set<Int>,
              _ body: (inout PKStroke) -> Void) -> Set<StrokeID> {
        var list = page.drawing.strokes
        for i in indices where list.indices.contains(i) { body(&list[i]) }
        page.setDrawing(PKDrawing(strokes: list), undoName: String(localized: name))
        let ids = page.strokeIDs
        return Set(indices.sorted().compactMap { ids.indices.contains($0) ? ids[$0] : nil })
    }

    func indices(of strokeIDs: Set<StrokeID>) -> Set<Int> {
        Set(page.strokeIDs.enumerated().compactMap { strokeIDs.contains($0.element) ? $0.offset : nil })
    }

    func strokes(intersecting polygon: [CGPoint]) -> [IdentifiedStroke] {
        guard polygon.count >= 3 else { return [] }
        let area = PolygonMath.bounds(of: polygon)
        return strokes.filter { Self.stroke($0.stroke, intersects: polygon, area: area) }
    }

    func render(strokeIDs: Set<StrokeID>, scale: CGFloat) -> UIImage? {
        let chosen = strokes.filter { strokeIDs.contains($0.id) }.map(\.stroke)
        guard !chosen.isEmpty else { return nil }
        let drawing = PKDrawing(strokes: chosen)
        let bounds = drawing.bounds.insetBy(dx: -4, dy: -4)
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        return drawing.image(from: bounds, scale: scale)
    }

    /// Cheap bounding-box test first, then the stroke's sampled points and segments against the lasso polygon.
    static func stroke(_ stroke: PKStroke, intersects polygon: [CGPoint], area: CGRect) -> Bool {
        guard stroke.renderBounds.intersects(area) else { return false }
        var previous: CGPoint?
        for point in stroke.path.interpolatedPoints(by: .distance(6)) {
            let p = point.location.applying(stroke.transform)
            if PolygonMath.contains(polygon, p) { return true }
            if let previous, segmentCrossesPolygon(previous, p, polygon) { return true }
            previous = p
        }
        return false
    }

    private static func segmentCrossesPolygon(_ a: CGPoint, _ b: CGPoint, _ polygon: [CGPoint]) -> Bool {
        for i in polygon.indices {
            let c = polygon[i], d = polygon[(i + 1) % polygon.count]
            if PolygonMath.segmentsIntersect(a, b, c, d) { return true }
        }
        return false
    }
}
