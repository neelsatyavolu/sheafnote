import UIKit
import SheafnoteCore

/// Forwards raw touches to `InkTouchObserver`s without ever taking part in gesture arbitration: it stays in the
/// possible state, never cancels or delays touches, and so cannot disturb PencilKit's drawing or scrolling.
final class InkTouchForwarder: UIGestureRecognizer {
    var onBegan: ((InkSample) -> Void)?
    var onMoved: (([InkSample]) -> Void)?
    var onEnded: ((InkSample) -> Void)?
    var onCancelled: (() -> Void)?
    /// Asked at touch-down: is any observer interested right now?
    var isWanted: (() -> Bool)?

    private var tracked: UITouch?

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard tracked == nil, touches.count == 1, let touch = touches.first, isWanted?() == true else { return }
        tracked = touch
        onBegan?(sample(touch))
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let tracked, touches.contains(tracked) else { return }
        if (event.allTouches?.count ?? 1) > 1 { cancelTracking(); return }
        let coalesced = event.coalescedTouches(for: tracked) ?? [tracked]
        onMoved?(coalesced.map(sample))
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let tracked, touches.contains(tracked) else { return }
        self.tracked = nil
        onEnded?(sample(tracked))
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let tracked, touches.contains(tracked) else { return }
        cancelTracking()
    }

    override func reset() { tracked = nil }

    private func cancelTracking() {
        tracked = nil
        onCancelled?()
    }

    private func sample(_ touch: UITouch) -> InkSample {
        InkSample(location: touch.location(in: view), timestamp: touch.timestamp, force: touch.force,
                  altitude: touch.altitudeAngle, azimuth: touch.azimuthAngle(in: view), isPencil: touch.type == .pencil)
    }
}
