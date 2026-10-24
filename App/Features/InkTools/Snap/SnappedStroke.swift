import PencilKit
import UIKit
import SheafnoteCore

/// Builds the clean stroke that replaces a hand-drawn one: same ink, colour, transform and creation date, with the
/// points laid along a figure instead of the wobbly original.
enum SnappedStroke {
    /// Distance between control points on the clean path, in points.
    static let spacing: CGFloat = 2

    static func make(replacing stroke: PKStroke, with figure: ShapeFigure) -> PKStroke {
        make(replacing: stroke, pagePoints: figure.outline(spacing: spacing, arrowLineWidth: averageWidth(of: stroke)))
    }

    static func line(replacing stroke: PKStroke, from a: CGPoint, to b: CGPoint) -> PKStroke {
        make(replacing: stroke, pagePoints: ShapeFigure.line(from: a, to: b).outline(spacing: spacing))
    }

    /// `pagePoints` are in page coordinates; the stroke's own transform is undone so the result lines up.
    static func make(replacing stroke: PKStroke, pagePoints: [CGPoint]) -> PKStroke {
        let original = Array(stroke.path)
        guard pagePoints.count >= 2, !original.isEmpty else { return stroke }
        let inverse = stroke.transform.inverted()
        let size = averageSize(original)
        let force = original.map { $0.force }.reduce(0, +) / CGFloat(original.count)
        let opacity = original.map { $0.opacity }.reduce(0, +) / CGFloat(original.count)
        let middle = original[original.count / 2]
        let duration = max(original.last?.timeOffset ?? 0.1, 0.05)
        let count = pagePoints.count
        let points = pagePoints.enumerated().map { index, point in
            PKStrokePoint(location: point.applying(inverse), timeOffset: duration * Double(index) / Double(max(count - 1, 1)),
                          size: size, opacity: opacity, force: force, azimuth: middle.azimuth, altitude: middle.altitude)
        }
        let path = PKStrokePath(controlPoints: points, creationDate: stroke.path.creationDate)
        return PKStroke(ink: stroke.ink, path: path, transform: stroke.transform, mask: stroke.mask)
    }

    static func averageWidth(of stroke: PKStroke) -> CGFloat { averageSize(Array(stroke.path)).width }

    private static func averageSize(_ points: [PKStrokePoint]) -> CGSize {
        guard !points.isEmpty else { return CGSize(width: 3, height: 3) }
        let n = CGFloat(points.count)
        return CGSize(width: points.map { $0.size.width }.reduce(0, +) / n, height: points.map { $0.size.height }.reduce(0, +) / n)
    }
}

/// A plain stroke through points, for a shape gesture that turned out not to be a shape.
enum FreehandStroke {
    static func make(points: [CGPoint], colorHex: String, width: Double, date: Date = .now) -> PKStroke? {
        guard points.count >= 2 else { return nil }
        let size = CGSize(width: width, height: width)
        let controls = points.enumerated().map { index, point in
            PKStrokePoint(location: point, timeOffset: Double(index) * 0.008, size: size, opacity: 1, force: 1,
                          azimuth: 0, altitude: .pi / 2)
        }
        let ink = PKInk(.pen, color: UIColor(hex: colorHex))
        return PKStroke(ink: ink, path: PKStrokePath(controlPoints: controls, creationDate: date))
    }
}
