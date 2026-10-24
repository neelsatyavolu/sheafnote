import CoreGraphics
import Foundation

/// Maps between a page (points, origin top-left) and the rectangle where a mirror shows it, letterboxed to keep the
/// page's proportions. Used by the external display and the on-device presenter.
public struct AspectFit: Sendable, Equatable {
    public let content: CGSize
    public let rect: CGRect

    public init(content: CGSize, in container: CGSize) {
        self.content = content
        guard content.width > 0, content.height > 0, container.width > 0, container.height > 0 else {
            rect = .zero
            return
        }
        let scale = min(container.width / content.width, container.height / content.height)
        let size = CGSize(width: content.width * scale, height: content.height * scale)
        rect = CGRect(x: (container.width - size.width) / 2, y: (container.height - size.height) / 2,
                      width: size.width, height: size.height)
    }

    /// View points per page point.
    public var scale: CGFloat { content.width > 0 ? rect.width / content.width : 0 }

    public func viewPoint(forPage point: CGPoint) -> CGPoint {
        CGPoint(x: rect.minX + point.x * scale, y: rect.minY + point.y * scale)
    }

    /// Nil when the view point lies outside the page.
    public func pagePoint(forView point: CGPoint) -> CGPoint? {
        guard scale > 0, rect.contains(point) else { return nil }
        return CGPoint(x: (point.x - rect.minX) / scale, y: (point.y - rect.minY) / scale)
    }
}
