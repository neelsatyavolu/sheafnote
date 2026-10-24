import CoreGraphics
import Foundation

/// Front and back regions of a flashcard on a page, in page coordinates.
public struct CardRegions: Equatable, Sendable {
    public var front: CGRect
    public var back: CGRect

    public static let minimumSide: CGFloat = 32

    public init(front: CGRect, back: CGRect) {
        self.front = front
        self.back = back
    }

    /// Both regions pulled inside the page and made at least `minimumSide` wide and tall.
    public func clamped(to page: CGSize) -> CardRegions {
        CardRegions(front: Self.clamp(front, to: page), back: Self.clamp(back, to: page))
    }

    public static func clamp(_ rect: CGRect, to page: CGSize) -> CGRect {
        guard page.width > 0, page.height > 0 else { return rect }
        let w = min(max(rect.width, minimumSide), page.width)
        let h = min(max(rect.height, minimumSide), page.height)
        let x = min(max(rect.minX, 0), page.width - w)
        let y = min(max(rect.minY, 0), page.height - h)
        return CGRect(x: x, y: y, width: w, height: h)
    }

    /// Starting regions for a lasso selection: the selection is the front, the back is a same-sized area just below
    /// it, or above it when the selection sits near the bottom of the page.
    public static func initial(forSelection selection: CGRect, in page: CGSize, gap: CGFloat = 16) -> CardRegions {
        let front = clamp(selection.insetBy(dx: -8, dy: -8), to: page)
        var back = front.offsetBy(dx: 0, dy: front.height + gap)
        if back.maxY > page.height { back = front.offsetBy(dx: 0, dy: -(front.height + gap)) }
        return CardRegions(front: front, back: clamp(back, to: page))
    }

    /// Starting regions with nothing selected: the top and the next quarter of the page.
    public static func initial(in page: CGSize) -> CardRegions {
        let w = page.width * 0.8, h = page.height * 0.18
        let x = (page.width - w) / 2
        return CardRegions(front: clamp(CGRect(x: x, y: page.height * 0.1, width: w, height: h), to: page),
                           back: clamp(CGRect(x: x, y: page.height * 0.34, width: w, height: h), to: page))
    }
}
