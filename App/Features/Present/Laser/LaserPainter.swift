import SwiftUI
import SheafnoteCore

/// Draws the laser (fading trail and glowing dot) in page coordinates. Shared by the page overlay and the mirrors.
enum LaserPainter {
    static func draw(_ model: LaserTrailModel, color: Color, diameter: CGFloat, now: TimeInterval, in context: inout GraphicsContext) {
        let visible = model.visiblePoints(at: now)
        guard !visible.isEmpty, diameter > 0 else { return }
        if visible.count > 1 { drawTrail(visible, color: color, diameter: diameter, in: &context) }
        if let head = model.head { drawDot(at: head, color: color, diameter: diameter, in: &context) }
    }

    private static func drawTrail(_ points: [LaserTrailModel.VisiblePoint], color: Color, diameter: CGFloat,
                                  in context: inout GraphicsContext) {
        for index in 1..<points.count {
            var segment = Path()
            segment.move(to: points[index - 1].location)
            segment.addLine(to: points[index].location)
            let alpha = points[index].opacity
            context.stroke(segment, with: .color(color.opacity(alpha * 0.85)),
                           style: StrokeStyle(lineWidth: max(diameter * 0.55 * alpha, 1), lineCap: .round, lineJoin: .round))
        }
    }

    private static func drawDot(at point: CGPoint, color: Color, diameter: CGFloat, in context: inout GraphicsContext) {
        let glow = diameter * 1.9
        context.fill(Path(ellipseIn: CGRect(x: point.x - glow / 2, y: point.y - glow / 2, width: glow, height: glow)),
                     with: .color(color.opacity(0.3)))
        context.fill(Path(ellipseIn: CGRect(x: point.x - diameter / 2, y: point.y - diameter / 2, width: diameter, height: diameter)),
                     with: .color(color))
        let core = diameter * 0.35
        context.fill(Path(ellipseIn: CGRect(x: point.x - core / 2, y: point.y - core / 2, width: core, height: core)),
                     with: .color(.white.opacity(0.9)))
    }
}
