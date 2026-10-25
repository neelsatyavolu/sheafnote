import CoreGraphics
import Foundation

/// Facing pages for a display divided by a fold (iPhone Duo held open like a book): pages go two to a spread, left
/// and right of a gutter wide enough that the fold falls between them instead of across a page. Units are page points
/// at zoom 1.
public enum FoldSpread {
    public struct Slot: Equatable, Sendable {
        /// The page.
        public let frame: CGRect
        /// Both pages of the page's spread and the gutter between them.
        public let spread: CGRect
    }

    /// The gutter that, at the zoom fitting a spread into `viewport`, is at least `foldWidth` screen points wide.
    /// `columnWidth` is one page plus its outer margin. `spreadHeight` (page plus both margins) is given when the fit
    /// also has to keep the whole spread in view; nil when only the width is fitted. Nil when the fold leaves no room.
    public static func gutter(columnWidth: CGFloat, spreadHeight: CGFloat?, viewport: CGSize, foldWidth: CGFloat) -> CGFloat? {
        guard columnWidth > 0, foldWidth > 0, viewport.height > 0, foldWidth < viewport.width / 2 else { return nil }
        // Width fit: zoom = w / (2c + g), and zoom * g >= fold  =>  g >= 2c * fold / (w - fold).
        let widthGutter = 2 * columnWidth * foldWidth / (viewport.width - foldWidth)
        // Height fit: zoom = h / H, independent of the gutter  =>  g >= fold * H / h.
        let heightGutter = spreadHeight.map { foldWidth * $0 / viewport.height } ?? 0
        return max(widthGutter, heightGutter)
    }

    /// How many tiles at least `minimum` wide fit across `width`, rounded down to an even count so a fold down the
    /// middle falls between two columns. Never less than one.
    public static func evenColumnCount(width: CGFloat, minimum: CGFloat, spacing: CGFloat) -> Int {
        guard minimum + spacing > 0 else { return 1 }
        let fitting = Int(((width + spacing) / (minimum + spacing)).rounded(.down))
        return fitting < 2 ? 1 : fitting - fitting % 2
    }

    /// Lays out pages two to a spread. Vertical spreads stack top to bottom and share one column width; horizontal
    /// spreads run left to right, each as wide as its own pages. Each page is centered in its column, and a lone last
    /// page takes the left column.
    public static func layout(sizes: [CGSize], gutter: CGFloat, margin: CGFloat, spacing: CGFloat,
                              horizontal: Bool) -> (slots: [Slot], contentSize: CGSize) {
        guard !sizes.isEmpty else { return ([], .zero) }
        let pairs = stride(from: 0, to: sizes.count, by: 2).map { Array(sizes[$0..<min($0 + 2, sizes.count)]) }
        let sharedColumn = sizes.map(\.width).max() ?? 0
        let sharedHeight = sizes.map(\.height).max() ?? 0
        var slots: [Slot] = []
        var cursor = margin
        for pair in pairs {
            let column = horizontal ? (pair.map(\.width).max() ?? 0) : sharedColumn
            let height = horizontal ? sharedHeight : (pair.map(\.height).max() ?? 0)
            let spread = horizontal
                ? CGRect(x: cursor, y: margin, width: 2 * column + gutter, height: height)
                : CGRect(x: margin, y: cursor, width: 2 * column + gutter, height: height)
            for (side, size) in pair.enumerated() {
                let columnX = spread.minX + CGFloat(side) * (column + gutter)
                let frame = CGRect(x: columnX + (column - size.width) / 2, y: spread.minY + (height - size.height) / 2,
                                   width: size.width, height: size.height)
                slots.append(Slot(frame: frame, spread: spread))
            }
            cursor += (horizontal ? spread.width : spread.height) + spacing
        }
        let end = cursor - spacing + margin
        let size = horizontal
            ? CGSize(width: end, height: sharedHeight + 2 * margin)
            : CGSize(width: 2 * sharedColumn + gutter + 2 * margin, height: end)
        return (slots, size)
    }
}
