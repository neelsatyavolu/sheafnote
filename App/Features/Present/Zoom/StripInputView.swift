import SwiftUI
import UIKit

/// Raw touches for the zoom strip (with coalesced samples and Pencil angles), which a SwiftUI drag cannot provide.
struct StripInputView: UIViewRepresentable {
    var acceptsFingers: Bool
    var onBegan: ([StripSample]) -> Void
    var onMoved: ([StripSample]) -> Void
    var onEnded: ([StripSample]) -> Void
    var onCancelled: () -> Void

    func makeUIView(context: Context) -> StripTouchView {
        let view = StripTouchView()
        view.isMultipleTouchEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ view: StripTouchView, context: Context) {
        view.acceptsFingers = acceptsFingers
        view.onBegan = onBegan
        view.onMoved = onMoved
        view.onEnded = onEnded
        view.onCancelled = onCancelled
    }
}

final class StripTouchView: UIView {
    var acceptsFingers = true
    var onBegan: ([StripSample]) -> Void = { _ in }
    var onMoved: ([StripSample]) -> Void = { _ in }
    var onEnded: ([StripSample]) -> Void = { _ in }
    var onCancelled: () -> Void = {}
    private var tracked: UITouch?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard tracked == nil, let touch = touches.first, accepts(touch) else { return }
        tracked = touch
        onBegan(samples(for: touch, event: event, includeCoalesced: false))
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = tracked, touches.contains(touch) else { return }
        onMoved(samples(for: touch, event: event, includeCoalesced: true))
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = tracked, touches.contains(touch) else { return }
        tracked = nil
        onEnded(samples(for: touch, event: event, includeCoalesced: true))
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = tracked, touches.contains(touch) else { return }
        tracked = nil
        onCancelled()
    }

    private func accepts(_ touch: UITouch) -> Bool { acceptsFingers || touch.type == .pencil }

    private func samples(for touch: UITouch, event: UIEvent?, includeCoalesced: Bool) -> [StripSample] {
        let touches = includeCoalesced ? (event?.coalescedTouches(for: touch) ?? [touch]) : [touch]
        return touches.map { item in
            StripSample(location: item.location(in: self), time: item.timestamp,
                        azimuth: item.type == .pencil ? item.azimuthAngle(in: self) : 0,
                        altitude: item.type == .pencil ? item.altitudeAngle : .pi / 2)
        }
    }
}
