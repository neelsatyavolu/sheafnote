import CoreGraphics
import Foundation

/// Time-based model of the laser pointer: a dot under the finger or Pencil, optionally with a trail that fades out.
/// Pure value type. The laser never writes ink; this is only what the overlay (and the presentation mirror) draws.
public struct LaserTrailModel: Sendable, Equatable {
    public enum Style: String, Codable, CaseIterable, Sendable {
        case dot
        case trail
    }

    public struct TimedPoint: Sendable, Equatable {
        public var location: CGPoint
        public var time: TimeInterval
    }

    public struct VisiblePoint: Sendable, Equatable {
        public var location: CGPoint
        /// 1 when fresh, 0 when fully faded.
        public var opacity: Double
    }

    public static let fadeRange: ClosedRange<TimeInterval> = 0.1...5

    public var style: Style
    public private(set) var fadeDuration: TimeInterval
    public private(set) var maxPoints: Int
    public private(set) var points: [TimedPoint] = []
    public private(set) var isDown = false
    private var lastUpdate: TimeInterval = 0

    public init(style: Style = .trail, fadeDuration: TimeInterval = 1, maxPoints: Int = 120) {
        self.style = style
        self.fadeDuration = min(max(fadeDuration, Self.fadeRange.lowerBound), Self.fadeRange.upperBound)
        self.maxPoints = max(2, maxPoints)
    }

    public var isEmpty: Bool { points.isEmpty }

    /// Where the dot is drawn: the newest point while the pointer is down.
    public var head: CGPoint? { isDown ? points.last?.location : nil }

    public mutating func begin(at location: CGPoint, time: TimeInterval) {
        isDown = true
        append(location, time: time)
    }

    public mutating func move(to location: CGPoint, time: TimeInterval) {
        guard isDown else { return begin(at: location, time: time) }
        append(location, time: time)
    }

    public mutating func end(time: TimeInterval) {
        isDown = false
        lastUpdate = max(lastUpdate, time)
    }

    public mutating func clear() {
        points.removeAll()
        isDown = false
    }

    /// Drops points whose trail has completely faded.
    public mutating func prune(now: TimeInterval) {
        points.removeAll { now - $0.time >= fadeDuration }
    }

    public func opacity(ofPointAt index: Int, now: TimeInterval) -> Double {
        guard points.indices.contains(index) else { return 0 }
        let age = now - points[index].time
        return min(max(1 - age / fadeDuration, 0), 1)
    }

    /// What to draw at `now`, oldest first.
    public func visiblePoints(at now: TimeInterval) -> [VisiblePoint] {
        switch style {
        case .dot:
            return head.map { [VisiblePoint(location: $0, opacity: 1)] } ?? []
        case .trail:
            return points.indices.compactMap { index in
                let alpha = opacity(ofPointAt: index, now: now)
                return alpha > 0 ? VisiblePoint(location: points[index].location, opacity: alpha) : nil
            }
        }
    }

    /// True once the pointer is up and the last movement has faded, so animation can stop.
    public func isFadedOut(at now: TimeInterval) -> Bool {
        guard !isDown else { return false }
        return points.isEmpty || now - lastUpdate >= fadeDuration
    }

    private mutating func append(_ location: CGPoint, time: TimeInterval) {
        points.append(TimedPoint(location: location, time: time))
        if points.count > maxPoints { points.removeFirst(points.count - maxPoints) }
        lastUpdate = time
    }
}
