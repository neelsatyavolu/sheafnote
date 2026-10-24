import CoreGraphics
import SheafnoteCore

/// CoreGraphics paths for a figure. Ellipses stay exact at any zoom; everything else is straight segments or a
/// finely sampled arc.
enum ShapeCGPath {
    static func path(for figure: ShapeFigure, lineWidth: CGFloat) -> CGPath {
        switch figure {
        case .ellipse(let center, let radii, let rotation):
            var transform = CGAffineTransform(translationX: center.x, y: center.y).rotated(by: CGFloat(rotation))
            let rect = CGRect(x: -radii.width, y: -radii.height, width: radii.width * 2, height: radii.height * 2)
            return CGPath(ellipseIn: rect, transform: &transform)
        default:
            let path = CGMutablePath()
            for line in figure.polylines(arrowLineWidth: lineWidth) {
                guard let first = line.first else { continue }
                path.move(to: first)
                line.dropFirst().forEach { path.addLine(to: $0) }
                if figure.isClosed { path.closeSubpath() }
            }
            return path
        }
    }

    /// Arcs are sampled coarsely by `polylines`; drawing wants them smooth.
    static func drawingPath(for figure: ShapeFigure, lineWidth: CGFloat) -> CGPath {
        guard case .arc = figure else { return path(for: figure, lineWidth: lineWidth) }
        let path = CGMutablePath()
        let points = figure.outline(spacing: 2)
        guard let first = points.first else { return path }
        path.move(to: first)
        points.dropFirst().forEach { path.addLine(to: $0) }
        return path
    }
}
