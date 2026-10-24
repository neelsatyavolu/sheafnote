import CoreGraphics
import Foundation

/// What copy/cut put on the pasteboard under `pasteboardType`: ink as `PKDrawing` data plus element values.
public struct SelectionClipboard: Codable, Equatable, Sendable {
    public static let pasteboardType = "co.xanom.sheafnote.selection"
    public static let currentVersion = 1

    public var version: Int
    /// `PKDrawing.dataRepresentation()`; empty when only elements were copied.
    public var strokes: Data
    public var elements: [ElementValue]
    /// Page coordinates of the copied selection.
    public var bounds: CGRect
    public var sourcePageID: UUID?

    public init(strokes: Data, elements: [ElementValue], bounds: CGRect, sourcePageID: UUID?) {
        self.version = Self.currentVersion
        self.strokes = strokes
        self.elements = elements
        self.bounds = bounds
        self.sourcePageID = sourcePageID
    }

    public var isEmpty: Bool { strokes.isEmpty && elements.isEmpty }

    public func encoded() -> Data { JSONCoding.encode(self) }

    /// Nil for data that is not ours, damaged, or written by a newer app version.
    public static func decode(_ data: Data) -> SelectionClipboard? {
        guard let value = JSONCoding.decode(SelectionClipboard.self, from: data), value.version <= currentVersion, !value.isEmpty else {
            return nil
        }
        return value
    }

    /// The elements as new copies for `pageID`: fresh ids, the page set, stacked above `topZIndex`, moved by `offset`.
    public func elementCopies(for pageID: UUID, offset: CGSize, topZIndex: Int) -> [ElementValue] {
        let move = CGAffineTransform(translationX: offset.width, y: offset.height)
        return elements.sorted { $0.zIndex < $1.zIndex }.enumerated().map { index, element in
            var copy = OrientedBoxHitTester(element: element).transformed(by: move)
            copy.id = UUID()
            copy.pageID = pageID
            copy.zIndex = topZIndex + 1 + index
            return copy
        }
    }
}

/// Where pasted content lands.
public enum PastePlacement {
    /// Distance each repeated paste on the same page steps away from the original.
    public static let nudge: CGFloat = 24

    /// Same page: step down-right by `nudge` per earlier paste, so copies never sit exactly on the original (ink with
    /// identical content would get an identical stroke id). Other page: same position. Either way the content is moved
    /// back inside the page, and pinned to the top-left when it is larger than the page.
    public static func offset(for bounds: CGRect, sourcePageID: UUID?, targetPageID: UUID,
                              targetSize: CGSize, earlierPastes: Int) -> CGSize {
        let samePage = sourcePageID == targetPageID
        let step = nudge * CGFloat(earlierPastes + 1)
        let first = fitted(bounds, shift: samePage ? step : 0, in: targetSize)
        // Pushed back onto the original by the page edge: step the other way instead.
        if samePage, abs(first.width) < 1, abs(first.height) < 1 { return fitted(bounds, shift: -step, in: targetSize) }
        return first
    }

    private static func fitted(_ bounds: CGRect, shift: CGFloat, in size: CGSize) -> CGSize {
        let moved = bounds.offsetBy(dx: shift, dy: shift)
        return CGSize(width: shift + correction(low: moved.minX, high: moved.maxX, limit: size.width),
                      height: shift + correction(low: moved.minY, high: moved.maxY, limit: size.height))
    }

    private static func correction(low: CGFloat, high: CGFloat, limit: CGFloat) -> CGFloat {
        if high - low >= limit { return -low }
        if low < 0 { return -low }
        if high > limit { return limit - high }
        return 0
    }
}
