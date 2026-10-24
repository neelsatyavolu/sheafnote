import CoreGraphics
import Foundation

/// A stroke written at `offset` seconds into a recording.
public struct AudioStrokeMark: Codable, Hashable, Sendable {
    public var pageID: UUID
    public var strokeID: StrokeID
    public var offset: Double

    public init(pageID: UUID, strokeID: StrokeID, offset: Double) {
        self.pageID = pageID
        self.strokeID = strokeID
        self.offset = offset
    }
}

/// A stroke as the timeline sees it: its id and the date PencilKit stamped on it.
public struct TimedStroke: Hashable, Sendable {
    public var id: StrokeID
    public var creationDate: Date

    public init(id: StrokeID, creationDate: Date) {
        self.id = id
        self.creationDate = creationDate
    }
}

/// Maps strokes to moments in a recording. Strokes carry creation dates, so the mapping works even for strokes
/// the recorder never saw (for example ink synced from another device); captured marks win when present.
public struct AudioTimeline: Equatable, Sendable {
    public var startedAt: Date
    public var duration: Double
    public var marks: [AudioStrokeMark]

    /// Strokes dated this far outside the recording still count as part of it (clock jitter at the edges).
    public static let edgeTolerance: Double = 0.75

    public init(startedAt: Date, duration: Double, marks: [AudioStrokeMark] = []) {
        self.startedAt = startedAt
        self.duration = max(0, duration)
        self.marks = marks
    }

    public init(startedAt: Date, duration: Double, encodedMarks: Data) {
        self.init(startedAt: startedAt, duration: duration,
                  marks: JSONCoding.decode([AudioStrokeMark].self, from: encodedMarks) ?? [])
    }

    public var encodedMarks: Data { JSONCoding.encode(marks) }

    /// Seconds into the recording at which the stroke was written, or nil if it was not written during it.
    public func offset(for stroke: TimedStroke) -> Double? {
        if let mark = marks.first(where: { $0.strokeID == stroke.id }) { return clamp(mark.offset) }
        let raw = stroke.creationDate.timeIntervalSince(startedAt)
        guard raw >= -Self.edgeTolerance, raw <= duration + Self.edgeTolerance else { return nil }
        return clamp(raw)
    }

    /// Strokes written during the recording but after the playhead; the editor dims these.
    public func strokesAfter(playhead: Double, among strokes: [TimedStroke]) -> Set<StrokeID> {
        var out = Set<StrokeID>()
        for s in strokes {
            if let o = offset(for: s), o > playhead { out.insert(s.id) }
        }
        return out
    }

    /// Records a stroke the recorder just saw. Existing marks are never replaced.
    public func adding(_ mark: AudioStrokeMark) -> AudioTimeline {
        guard !marks.contains(where: { $0.strokeID == mark.strokeID }) else { return self }
        var copy = self
        copy.marks.append(mark)
        return copy
    }

    /// The same timeline with the final length once recording stops.
    public func finished(duration: Double) -> AudioTimeline {
        var copy = self
        copy.duration = max(0, duration)
        copy.marks = marks.map { AudioStrokeMark(pageID: $0.pageID, strokeID: $0.strokeID, offset: min($0.offset, copy.duration)) }
        return copy
    }

    private func clamp(_ t: Double) -> Double { min(max(0, t), duration) }
}

/// Which stroke a tap meant. Strokes are given as sampled polylines in page coordinates.
public enum StrokeSeekHitTest {
    public static func nearest(to point: CGPoint, among strokes: [(id: StrokeID, points: [CGPoint])],
                               tolerance: CGFloat) -> StrokeID? {
        var best: (id: StrokeID, distance: CGFloat)?
        for stroke in strokes {
            let d = distance(from: point, to: stroke.points)
            guard d <= tolerance else { continue }
            if best == nil || d < best!.distance { best = (stroke.id, d) }
        }
        return best?.id
    }

    static func distance(from p: CGPoint, to polyline: [CGPoint]) -> CGFloat {
        guard let first = polyline.first else { return .infinity }
        if polyline.count == 1 { return hypot(p.x - first.x, p.y - first.y) }
        var best = CGFloat.infinity
        for i in 1..<polyline.count { best = min(best, segmentDistance(p, polyline[i - 1], polyline[i])) }
        return best
    }

    private static func segmentDistance(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return hypot(p.x - a.x, p.y - a.y) }
        let t = min(1, max(0, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared))
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }
}
