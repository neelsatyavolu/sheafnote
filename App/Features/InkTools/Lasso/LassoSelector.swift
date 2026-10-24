import PencilKit
import SheafnoteCore

/// Works out what a lasso, a tap or "select all" picks up on a page.
@MainActor
struct LassoSelector {
    struct Pick: Equatable {
        var strokeIDs: Set<StrokeID>
        var elementIDs: Set<UUID>
        var bounds: CGRect
    }

    let host: FeatureHost

    // MARK: Entry points

    /// Everything the filters allow that the freeform path touches.
    func pick(inside polygon: [CGPoint], on page: any PageContext, filters: LassoFilters) -> Pick? {
        let strokes = filters.contains(.handwriting) ? page.ink.strokes(intersecting: polygon) : []
        let elements = page.elements.all.filter { filters.accepts($0.kind) && hitTester(for: $0).intersects(polygon: polygon) }
        return pick(strokes: strokes, elements: elements)
    }

    /// The topmost element, else the nearest stroke, within reach of the tapped point.
    func pick(at point: CGPoint, on page: any PageContext, filters: LassoFilters) -> Pick? {
        let reach = LassoGeometry.tapReach(zoom: page.zoomScale)
        let elements = page.elements.all.sorted { $0.zIndex > $1.zIndex }
        if let element = elements.first(where: { filters.accepts($0.kind) && hitTester(for: $0).contains(point: point) }) {
            return pick(strokes: [], elements: [element])
        }
        guard filters.contains(.handwriting) else { return nil }
        guard let stroke = page.ink.strokes.last(where: { Self.stroke($0.stroke, isWithin: reach, of: point) }) else { return nil }
        return pick(strokes: [stroke], elements: [])
    }

    func pickAll(on page: any PageContext, filters: LassoFilters) -> Pick? {
        let strokes = filters.contains(.handwriting) ? page.ink.strokes : []
        return pick(strokes: strokes, elements: page.elements.all.filter { filters.accepts($0.kind) })
    }

    func hitTester(for element: ElementValue) -> any ElementHitTesting {
        host.elementRenderers.renderer(for: element.kind)?.hitTester(for: element) ?? OrientedBoxHitTester(element: element)
    }

    // MARK: Helpers

    private func pick(strokes: [IdentifiedStroke], elements: [ElementValue]) -> Pick? {
        let rects = strokes.map(\.stroke.renderBounds) + elements.map { hitTester(for: $0).bounds }
        guard let bounds = LassoGeometry.union(rects) else { return nil }
        return Pick(strokeIDs: Set(strokes.map(\.id)), elementIDs: Set(elements.map(\.id)), bounds: bounds)
    }

    static func stroke(_ stroke: PKStroke, isWithin reach: CGFloat, of point: CGPoint) -> Bool {
        guard stroke.renderBounds.insetBy(dx: -reach, dy: -reach).contains(point) else { return false }
        return stroke.path.interpolatedPoints(by: .distance(4)).contains { sample in
            let location = sample.location.applying(stroke.transform)
            return hypot(location.x - point.x, location.y - point.y) <= reach + sample.size.width / 2
        }
    }
}
