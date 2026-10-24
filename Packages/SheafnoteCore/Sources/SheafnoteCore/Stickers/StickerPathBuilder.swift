import CoreGraphics
import Foundation

/// Helpers that produce sticker outlines. All results are plain command lists (path data), so stickers stay vector.
public enum StickerPathBuilder {
    private static let kappa: CGFloat = 0.5522847498

    public static func polygon(_ points: [CGPoint]) -> [StickerCommand] {
        guard let first = points.first else { return [] }
        return [.move(first)] + points.dropFirst().map { .line($0) } + [.close]
    }

    public static func rect(_ r: CGRect) -> [StickerCommand] {
        polygon([CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
                 CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.minX, y: r.maxY)])
    }

    public static func roundedRect(_ r: CGRect, radius: CGFloat) -> [StickerCommand] {
        let rad = min(radius, min(r.width, r.height) / 2)
        let c = rad * kappa
        return [
            .move(CGPoint(x: r.minX + rad, y: r.minY)),
            .line(CGPoint(x: r.maxX - rad, y: r.minY)),
            .curve(to: CGPoint(x: r.maxX, y: r.minY + rad),
                   control1: CGPoint(x: r.maxX - rad + c, y: r.minY), control2: CGPoint(x: r.maxX, y: r.minY + rad - c)),
            .line(CGPoint(x: r.maxX, y: r.maxY - rad)),
            .curve(to: CGPoint(x: r.maxX - rad, y: r.maxY),
                   control1: CGPoint(x: r.maxX, y: r.maxY - rad + c), control2: CGPoint(x: r.maxX - rad + c, y: r.maxY)),
            .line(CGPoint(x: r.minX + rad, y: r.maxY)),
            .curve(to: CGPoint(x: r.minX, y: r.maxY - rad),
                   control1: CGPoint(x: r.minX + rad - c, y: r.maxY), control2: CGPoint(x: r.minX, y: r.maxY - rad + c)),
            .line(CGPoint(x: r.minX, y: r.minY + rad)),
            .curve(to: CGPoint(x: r.minX + rad, y: r.minY),
                   control1: CGPoint(x: r.minX, y: r.minY + rad - c), control2: CGPoint(x: r.minX + rad - c, y: r.minY)),
            .close,
        ]
    }

    public static func ellipse(in r: CGRect) -> [StickerCommand] {
        let cx = r.midX, cy = r.midY, rx = r.width / 2, ry = r.height / 2
        let kx = rx * kappa, ky = ry * kappa
        return [
            .move(CGPoint(x: cx + rx, y: cy)),
            .curve(to: CGPoint(x: cx, y: cy + ry), control1: CGPoint(x: cx + rx, y: cy + ky), control2: CGPoint(x: cx + kx, y: cy + ry)),
            .curve(to: CGPoint(x: cx - rx, y: cy), control1: CGPoint(x: cx - kx, y: cy + ry), control2: CGPoint(x: cx - rx, y: cy + ky)),
            .curve(to: CGPoint(x: cx, y: cy - ry), control1: CGPoint(x: cx - rx, y: cy - ky), control2: CGPoint(x: cx - kx, y: cy - ry)),
            .curve(to: CGPoint(x: cx + rx, y: cy), control1: CGPoint(x: cx + kx, y: cy - ry), control2: CGPoint(x: cx + rx, y: cy - ky)),
            .close,
        ]
    }

    /// A star or burst with `points` tips, the first pointing up.
    public static func star(center: CGPoint, outer: CGFloat, inner: CGFloat, points: Int) -> [StickerCommand] {
        let tips = max(points, 3)
        let pts = (0..<(tips * 2)).map { i -> CGPoint in
            let radius = i.isMultiple(of: 2) ? outer : inner
            let angle = -CGFloat.pi / 2 + CGFloat(i) * .pi / CGFloat(tips)
            return CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
        }
        return polygon(pts)
    }

    /// A regular polygon with `sides` corners, the first pointing up unless rotated.
    public static func regularPolygon(center: CGPoint, radius: CGFloat, sides: Int, rotation: CGFloat = 0) -> [StickerCommand] {
        let n = max(sides, 3)
        return polygon((0..<n).map { i in
            let a = -CGFloat.pi / 2 + rotation + CGFloat(i) * 2 * .pi / CGFloat(n)
            return CGPoint(x: center.x + radius * cos(a), y: center.y + radius * sin(a))
        })
    }

    /// An open polyline (no closing), used for check marks, crosses and wave patterns.
    public static func polyline(_ points: [CGPoint]) -> [StickerCommand] {
        guard let first = points.first else { return [] }
        return [.move(first)] + points.dropFirst().map { .line($0) }
    }

    /// A rectangle strip whose short ends are torn in a zigzag, as washi tape is.
    public static func tornStrip(_ r: CGRect, teeth: Int, depth: CGFloat) -> [StickerCommand] {
        let step = r.height / CGFloat(teeth)
        var pts = [CGPoint(x: r.minX + depth, y: r.minY), CGPoint(x: r.maxX - depth, y: r.minY)]
        for i in 0..<teeth {
            pts.append(CGPoint(x: r.maxX, y: r.minY + step * (CGFloat(i) + 0.5)))
            pts.append(CGPoint(x: r.maxX - depth, y: r.minY + step * CGFloat(i + 1)))
        }
        pts.append(CGPoint(x: r.minX + depth, y: r.maxY))
        for i in (0..<teeth).reversed() {
            pts.append(CGPoint(x: r.minX, y: r.minY + step * (CGFloat(i) + 0.5)))
            pts.append(CGPoint(x: r.minX + depth, y: r.minY + step * CGFloat(i)))
        }
        return polygon(pts)
    }
}

public extension Array where Element == StickerCommand {
    /// Bounding box of every point used (control points included); a cheap superset of the drawn bounds.
    var pointBounds: CGRect {
        var pts: [CGPoint] = []
        for command in self {
            switch command {
            case .move(let p), .line(let p): pts.append(p)
            case .quad(let p, let c): pts += [p, c]
            case .curve(let p, let c1, let c2): pts += [p, c1, c2]
            case .close: break
            }
        }
        guard let first = pts.first else { return .null }
        return pts.dropFirst().reduce(CGRect(origin: first, size: .zero)) { $0.union(CGRect(origin: $1, size: .zero)) }
    }
}
