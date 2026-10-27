import PencilKit
import UIKit
import SheafnoteCore

/// Standard eraser: a pixel erase leaves slivers and nubs of the strokes it cut. This drops the pieces too small to be
/// real ink; which pieces count as crumbs is decided by `EraserCleanup` in core.
@MainActor
enum EraseCrumbs {
    static func removing(from erased: PKDrawing, since start: PKDrawing) -> PKDrawing {
        let before = Set(start.strokes.map(\.strokeID))
        let strokes = erased.strokes
        let pieces = EraserCleanup.changedIndices(before: before, after: strokes.map(\.strokeID))
        let crumbs = Set(pieces.filter { isCrumb(strokes[$0]) })
        guard !crumbs.isEmpty else { return erased }
        return PKDrawing(strokes: strokes.enumerated().filter { !crumbs.contains($0.offset) }.map(\.element))
    }

    private static func isCrumb(_ stroke: PKStroke) -> Bool {
        let bounds = stroke.renderBounds
        guard !bounds.isNull, !bounds.isInfinite, bounds.width > 0, bounds.height > 0 else { return true }
        let width = inkWidth(of: stroke)
        if EraserCleanup.isCrumb(visibleArea: bounds.width * bounds.height, inkWidth: width) { return true }
        // Render the piece on its own, small, and measure the ink that actually shows past the eraser's mask.
        let scale = min(1, 96 / max(bounds.width, bounds.height))
        guard let image = PKDrawing(strokes: [stroke]).image(from: bounds, scale: scale).cgImage else { return false }
        return EraserCleanup.isCrumb(visibleArea: EraserCleanup.inkArea(of: image, scale: scale), inkWidth: width)
    }

    /// Mean nib width along the path, in page points (a resized stroke carries its scale in the transform).
    private static func inkWidth(of stroke: PKStroke) -> Double {
        let widths = stroke.path.map { Double($0.size.width) }
        guard !widths.isEmpty else { return 0 }
        let t = stroke.transform
        return widths.reduce(0, +) / Double(widths.count) * Double(abs(t.a * t.d - t.b * t.c)).squareRoot()
    }
}
