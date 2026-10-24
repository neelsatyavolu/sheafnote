import CoreGraphics
import Foundation

/// Geometry for whiteboards: how far the canvas grows around what was drawn, and how far to zoom to fit it.
/// The canvas only ever grows; nothing here moves or removes content.
public enum CanvasBounds {
    /// Free space kept to the right of and below the content.
    public static let growthMargin: CGFloat = 800
    /// Canvas sizes are rounded up to a multiple of this, so it doesn't resize on every stroke.
    public static let growthStep: CGFloat = 400
    public static let maxFitScale: CGFloat = 4

    /// The size the canvas should have for `content`. Never smaller than `current` or `initial`.
    public static func grownSize(current: CGSize, content: CGRect?, initial: CGSize) -> CGSize {
        let floorSize = CGSize(width: max(current.width, initial.width), height: max(current.height, initial.height))
        guard let content, isUsable(content) else { return floorSize }
        return CGSize(width: grown(needed: content.maxX + growthMargin, floor: floorSize.width),
                      height: grown(needed: content.maxY + growthMargin, floor: floorSize.height))
    }

    /// Union of the ink bounds and element frames, or nil when the canvas is empty.
    public static func contentBounds(strokes: CGRect?, elements: [CGRect]) -> CGRect? {
        let all = ([strokes].compactMap { $0 } + elements).filter(isUsable)
        guard let first = all.first else { return nil }
        return all.dropFirst().reduce(first) { $0.union($1) }
    }

    /// Zoom that shows all of `content` inside `viewport` with `padding` points around it.
    public static func fitScale(content: CGRect, viewport: CGSize, padding: CGFloat) -> CGFloat {
        guard isUsable(content), viewport.width > 0, viewport.height > 0 else { return 1 }
        let availableWidth = max(viewport.width - 2 * padding, 1)
        let availableHeight = max(viewport.height - 2 * padding, 1)
        let scale = min(availableWidth / content.width, availableHeight / content.height)
        return min(scale, maxFitScale)
    }

    private static func grown(needed: CGFloat, floor: CGFloat) -> CGFloat {
        guard needed > floor else { return floor }
        return (needed / growthStep).rounded(.up) * growthStep
    }

    private static func isUsable(_ rect: CGRect) -> Bool {
        !rect.isNull && !rect.isInfinite && rect.width > 0 && rect.height > 0
            && rect.origin.x.isFinite && rect.origin.y.isFinite
    }
}
