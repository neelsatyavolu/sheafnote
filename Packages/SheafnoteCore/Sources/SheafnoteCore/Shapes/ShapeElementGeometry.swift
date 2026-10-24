import CoreGraphics
import Foundation

/// Geometry of a shape element on a page: the figure it draws and the tests the lasso needs.
public enum ShapeElementGeometry {
    /// The shape element for `figure`, ready to add to a page.
    public static func element(for figure: ShapeFigure, pageID: UUID, zIndex: Int, strokeHex: String,
                               fillHex: String?, lineWidth: Double) -> ElementValue {
        let placement = figure.placement(lineWidth: CGFloat(lineWidth))
        let payload = ShapePayload(shapeKind: placement.kind, points: placement.points, strokeHex: strokeHex,
                                   fillHex: figure.isClosed ? fillHex : nil, lineWidth: lineWidth)
        return ElementValue(pageID: pageID, kind: .shape, frame: placement.frame, rotation: placement.rotation,
                            zIndex: zIndex, payload: PayloadCodec.encode(payload))
    }

    /// The element with a new outline colour and/or line width. A damaged payload is returned unchanged.
    public static func restyled(_ element: ElementValue, strokeHex: String? = nil, lineWidth: Double? = nil) -> ElementValue {
        guard element.kind == .shape, var payload = PayloadCodec.decode(ShapePayload.self, from: element.payload) else { return element }
        if let strokeHex { payload.strokeHex = strokeHex }
        if let lineWidth { payload.lineWidth = lineWidth }
        var copy = element
        copy.payload = PayloadCodec.encode(payload)
        return copy
    }

    /// The element with its fill set (`nil` removes the fill). Open shapes (line, arrow, arc) cannot be filled and a
    /// damaged payload is returned unchanged.
    public static func refilled(_ element: ElementValue, fillHex: String?) -> ElementValue {
        guard element.kind == .shape, var payload = PayloadCodec.decode(ShapePayload.self, from: element.payload) else { return element }
        let closed: Set<ShapeKind> = [.rectangle, .ellipse, .triangle, .polygon]
        payload.fillHex = closed.contains(payload.shapeKind) ? fillHex : nil
        var copy = element
        copy.payload = PayloadCodec.encode(payload)
        return copy
    }

    /// The figure a shape element draws, in page coordinates (rotation applied). Nil for a damaged payload.
    public static func figure(of element: ElementValue) -> ShapeFigure? {
        guard element.kind == .shape, let payload = PayloadCodec.decode(ShapePayload.self, from: element.payload) else { return nil }
        return ShapeFigure(placement: ShapePlacement(kind: payload.shapeKind, frame: element.frame,
                                                     rotation: element.rotation, points: payload.points))
    }

    /// The figure in the element's own unrotated frame (origin at the frame's top-left), for drawing.
    public static func localFigure(of element: ElementValue) -> ShapeFigure? {
        guard let payload = PayloadCodec.decode(ShapePayload.self, from: element.payload) else { return nil }
        let frame = CGRect(origin: .zero, size: element.frame.size)
        return ShapeFigure(placement: ShapePlacement(kind: payload.shapeKind, frame: frame, rotation: 0, points: payload.points))
    }
}

/// Hit testing that follows the drawn outline instead of the element's bounding box, so a diagonal line is not
/// picked up by a lasso that only crosses the empty corner of its frame.
public struct ShapeHitTester: ElementHitTesting {
    public let element: ElementValue
    private let box: OrientedBoxHitTester
    private let lineWidth: CGFloat
    private let filled: Bool

    public init(element: ElementValue) {
        self.element = element
        self.box = OrientedBoxHitTester(element: element)
        let payload = PayloadCodec.decode(ShapePayload.self, from: element.payload)
        self.lineWidth = CGFloat(payload?.lineWidth ?? 3)
        self.filled = payload?.fillHex != nil
    }

    public var bounds: CGRect { box.bounds }

    public func intersects(polygon: [CGPoint]) -> Bool {
        guard let figure = ShapeElementGeometry.figure(of: element) else { return box.intersects(polygon: polygon) }
        let lines = figure.polylines(arrowLineWidth: lineWidth)
        if lines.contains(where: { LassoGeometry.polyline($0, intersects: polygon) }) { return true }
        // A lasso drawn entirely inside a filled shape selects it.
        return filled && figure.isClosed && polygon.first.map { PolygonMath.contains(lines.first ?? [], $0) } == true
    }

    public func contains(point: CGPoint) -> Bool {
        guard let figure = ShapeElementGeometry.figure(of: element) else { return box.contains(point: point) }
        let lines = figure.polylines(arrowLineWidth: lineWidth)
        let reach = max(lineWidth / 2 + 8, 10)
        if lines.contains(where: { ShapeFit.distanceToPolyline(point, $0, closed: false) <= reach }) { return true }
        return filled && figure.isClosed && PolygonMath.contains(lines.first ?? [], point)
    }

    public func transformed(by t: CGAffineTransform) -> ElementValue { box.transformed(by: t) }
}
