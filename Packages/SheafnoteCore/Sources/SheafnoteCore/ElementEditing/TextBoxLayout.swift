import CoreGraphics
import Foundation

/// Placement rules for text boxes and z-order of new elements.
public enum TextBoxLayout {
    public static let defaultSize = CGSize(width: 240, height: 48)
    public static let minimumSize = CGSize(width: 48, height: 28)
    /// Inner padding between the box edge and its text.
    public static let padding: CGFloat = 6

    /// The frame of a new text box whose top-left corner is at `tap`, shifted to stay on the page.
    public static func newFrame(at tap: CGPoint, pageSize: CGSize) -> CGRect {
        var size = defaultSize
        size.width = min(size.width, max(pageSize.width, minimumSize.width))
        let x = min(max(tap.x, 0), max(pageSize.width - size.width, 0))
        let y = min(max(tap.y, 0), max(pageSize.height - size.height, 0))
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }

    /// Height a box must have to show text that needs `contentHeight`; boxes never shrink below `minimumSize`.
    public static func fittedHeight(contentHeight: CGFloat, current: CGFloat) -> CGFloat {
        max(minimumSize.height, current, (contentHeight + padding * 2).rounded(.up))
    }

    /// One above every existing element.
    public static func nextZIndex(in elements: [ElementValue]) -> Int {
        (elements.map(\.zIndex).max() ?? -1) + 1
    }
}
