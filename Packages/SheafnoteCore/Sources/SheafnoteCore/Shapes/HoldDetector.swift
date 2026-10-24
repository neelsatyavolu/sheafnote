import CoreGraphics
import Foundation

/// Decides whether a pen is "held": it has stayed within `tolerance` points of one spot for `duration` seconds.
/// Pure state; the caller supplies timestamps and schedules its own wake-up using `remaining(at:)`.
public struct HoldDetector: Equatable, Sendable {
    public static let defaultTolerance: CGFloat = 2
    public static let defaultDuration: TimeInterval = 0.6

    public let tolerance: CGFloat
    public let duration: TimeInterval
    private var anchor: CGPoint?
    private var anchoredAt: TimeInterval = 0

    public init(tolerance: CGFloat = HoldDetector.defaultTolerance, duration: TimeInterval = HoldDetector.defaultDuration) {
        self.tolerance = tolerance
        self.duration = duration
    }

    public var isTracking: Bool { anchor != nil }

    public mutating func begin(at point: CGPoint, time: TimeInterval) {
        anchor = point
        anchoredAt = time
    }

    /// Movement beyond the tolerance restarts the hold from the new position.
    public mutating func move(to point: CGPoint, time: TimeInterval) {
        guard let anchor else { return begin(at: point, time: time) }
        if ShapeFit.distance(anchor, point) > tolerance {
            self.anchor = point
            anchoredAt = time
        }
    }

    public mutating func reset() { anchor = nil }

    public func isHeld(at time: TimeInterval) -> Bool {
        anchor != nil && time - anchoredAt >= duration
    }

    /// Seconds until the hold completes if the pen stays still; nil when not tracking.
    public func remaining(at time: TimeInterval) -> TimeInterval? {
        anchor == nil ? nil : max(duration - (time - anchoredAt), 0)
    }
}
