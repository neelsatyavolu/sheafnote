import CoreGraphics
import Foundation

/// Builds a figure of a chosen kind from a drag (the shapes tool with a fixed shape instead of "auto").
/// Corner-to-corner kinds use the drag's first and last point; an arc bulges towards the farthest point drawn.
public enum ShapeBuilder {
    static let minimumDragDistance: CGFloat = 12

    public static func figure(kind: ShapeKind, path: [CGPoint]) -> ShapeFigure? {
        guard let a = path.first, let b = path.last, ShapeFit.distance(a, b) >= minimumDragDistance else { return nil }
        let box = CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
        switch kind {
        case .line:
            let ends = StraightLineFit.snapped(from: a, to: b)
            return .line(from: ends.0, to: ends.1)
        case .arrow:
            let ends = StraightLineFit.snapped(from: a, to: b)
            return .arrow(from: ends.0, to: ends.1)
        case .rectangle:
            return solid(box) ? .rectangle(center: CGPoint(x: box.midX, y: box.midY), size: box.size, rotation: 0) : nil
        case .ellipse:
            return solid(box) ? ellipse(in: box) : nil
        case .triangle:
            guard solid(box) else { return nil }
            return .triangle([CGPoint(x: box.midX, y: box.minY), CGPoint(x: box.maxX, y: box.maxY), CGPoint(x: box.minX, y: box.maxY)])
        case .polygon:
            return solid(box) ? hexagon(in: box) : nil
        case .arc:
            return arc(path: path, from: a, to: b)
        }
    }

    private static func solid(_ box: CGRect) -> Bool { box.width >= 6 && box.height >= 6 }

    private static func ellipse(in box: CGRect) -> ShapeFigure {
        var radii = CGSize(width: box.width / 2, height: box.height / 2)
        if abs(radii.width - radii.height) <= 0.08 * max(radii.width, radii.height) {
            let r = (radii.width + radii.height) / 2
            radii = CGSize(width: r, height: r)
        }
        return .ellipse(center: CGPoint(x: box.midX, y: box.midY), radii: radii, rotation: 0)
    }

    private static func hexagon(in box: CGRect) -> ShapeFigure {
        let corners = (0..<6).map { i -> CGPoint in
            let angle = -Double.pi / 2 + Double.pi / 3 * Double(i)
            return CGPoint(x: box.midX + box.width / 2 * CGFloat(cos(angle)), y: box.midY + box.height / 2 * CGFloat(sin(angle)))
        }
        return .polygon(corners)
    }

    private static func arc(path: [CGPoint], from a: CGPoint, to b: CGPoint) -> ShapeFigure? {
        guard let bulge = path.max(by: { ShapeFit.distanceToSegment($0, a, b) < ShapeFit.distanceToSegment($1, a, b) }),
              ShapeFit.distanceToSegment(bulge, a, b) >= 4,
              let circle = ShapeFigure.circle(through: a, bulge, b) else { return nil }
        return .arc(center: circle.center, radius: circle.radius, startAngle: circle.start, sweep: circle.sweep)
    }
}

/// Which shape the shapes tool draws.
public enum ShapeMode: String, Codable, CaseIterable, Sendable {
    case auto, line, arrow, rectangle, ellipse, triangle, polygon, arc

    public var kind: ShapeKind? { ShapeKind(rawValue: rawValue) }
}

/// Persisted options of the shapes tool.
public struct ShapeToolSettings: Codable, Equatable, Sendable {
    public var mode: ShapeMode
    public var strokeHex: String
    public var fillHex: String?
    public var lineWidth: Double

    public init(mode: ShapeMode = .auto, strokeHex: String = "#2B2420", fillHex: String? = nil, lineWidth: Double = 3) {
        self.mode = mode; self.strokeHex = strokeHex; self.fillHex = fillHex; self.lineWidth = lineWidth
    }
}
