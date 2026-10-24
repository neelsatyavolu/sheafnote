import PencilKit
import UIKit

/// "Erase highlighter only": PencilKit's own erasers cannot skip pen strokes, so this one works on the strokes directly.
/// Hit testing is pure so it can be tested without a canvas.
enum MarkerEraser {
    /// Indices of marker (highlighter) strokes whose path passes within `radius` of any of `points`.
    static func markerStrokeIndices(in drawing: PKDrawing, near points: [CGPoint], radius: CGFloat) -> Set<Int> {
        guard !points.isEmpty else { return [] }
        var hits = Set<Int>()
        for (index, stroke) in drawing.strokes.enumerated() where stroke.ink.inkType == .marker {
            let reach = radius + 2
            let bounds = stroke.renderBounds.insetBy(dx: -reach, dy: -reach)
            let candidates = points.filter { bounds.contains($0) }
            guard !candidates.isEmpty else { continue }
            if touches(stroke, candidates: candidates, radius: radius) { hits.insert(index) }
        }
        return hits
    }

    private static func touches(_ stroke: PKStroke, candidates: [CGPoint], radius: CGFloat) -> Bool {
        for sample in stroke.path.interpolatedPoints(by: .distance(4)) {
            let p = sample.location.applying(stroke.transform)
            let reach = radius + max(sample.size.width, sample.size.height) / 2
            for c in candidates where hypot(c.x - p.x, c.y - p.y) <= reach { return true }
        }
        return false
    }

    static func removing(_ indices: Set<Int>, from drawing: PKDrawing) -> PKDrawing {
        guard !indices.isEmpty else { return drawing }
        let kept = drawing.strokes.enumerated().filter { !indices.contains($0.offset) }.map(\.element)
        return PKDrawing(strokes: kept)
    }
}

/// Tracks a Pencil or finger drag and reports its sample points. Only active while the highlighter-only eraser is chosen.
final class MarkerEraseRecognizer: UIGestureRecognizer {
    var onBegan: (() -> Void)?
    var onSamples: (([CGPoint]) -> Void)?
    var onEnded: (() -> Void)?

    private var tracked: UITouch?

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        cancelsTouchesInView = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard tracked == nil else { finish(.cancelled); return }
        guard let touch = touches.first, event.allTouches?.count == 1 else {
            state = .failed
            return
        }
        tracked = touch
        state = .began
        onBegan?()
        onSamples?([touch.location(in: view)])
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let tracked, touches.contains(tracked) else { return }
        if (event.allTouches?.count ?? 1) > 1 { finish(.cancelled); return }
        let coalesced = event.coalescedTouches(for: tracked) ?? [tracked]
        state = .changed
        onSamples?(coalesced.map { $0.location(in: view) })
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let tracked, touches.contains(tracked) else { return }
        finish(.ended)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let tracked, touches.contains(tracked) else { return }
        finish(.cancelled)
    }

    override func reset() { tracked = nil }

    private func finish(_ final: UIGestureRecognizer.State) {
        tracked = nil
        state = final
        onEnded?()
    }
}
