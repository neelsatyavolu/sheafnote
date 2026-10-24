import Foundation

/// SM-2 recall grade, 0 (blackout) to 5 (perfect). Grades of 3 and above count as a pass.
public struct SM2Grade: Hashable, Sendable, Comparable {
    public let rawValue: Int

    public init(clamping value: Int) { rawValue = min(5, max(0, value)) }

    public static let blackout = SM2Grade(clamping: 0)
    public static let again = SM2Grade(clamping: 1)
    public static let hard = SM2Grade(clamping: 3)
    public static let good = SM2Grade(clamping: 4)
    public static let easy = SM2Grade(clamping: 5)

    public var isPassing: Bool { rawValue >= 3 }
    public static func < (l: SM2Grade, r: SM2Grade) -> Bool { l.rawValue < r.rawValue }
}

/// The scheduling part of a `StudyState`, as a plain value.
public struct SM2Schedule: Equatable, Sendable {
    public var ease: Double
    public var intervalDays: Int
    public var repetitions: Int
    public var lapses: Int

    public init(ease: Double, intervalDays: Int, repetitions: Int, lapses: Int) {
        self.ease = ease
        self.intervalDays = intervalDays
        self.repetitions = repetitions
        self.lapses = lapses
    }

    public static let initial = SM2Schedule(ease: 2.5, intervalDays: 0, repetitions: 0, lapses: 0)
}

public struct SM2Review: Equatable, Sendable {
    public let schedule: SM2Schedule
    public let dueAt: Date
}

/// Basic SM-2: first pass 1 day, second pass 6 days, then interval times ease. A failed card goes back to
/// 1 day and counts a lapse. Ease moves with the grade and never drops below 1.3.
public enum SM2Scheduler {
    public static let minimumEase = 1.3
    public static let maximumIntervalDays = 36_500

    public static func review(_ s: SM2Schedule, grade: SM2Grade, at now: Date,
                              calendar: Calendar = .current) -> SM2Review {
        let miss = Double(5 - grade.rawValue)
        var next = s
        next.ease = max(minimumEase, s.ease + 0.1 - miss * (0.08 + miss * 0.02))
        if grade.isPassing {
            next.intervalDays = passingInterval(after: s)
            next.repetitions = s.repetitions + 1
        } else {
            next.intervalDays = 1
            next.repetitions = 0
            next.lapses = s.lapses + 1
        }
        let due = calendar.date(byAdding: .day, value: next.intervalDays, to: now)
            ?? now.addingTimeInterval(Double(next.intervalDays) * 86_400)
        return SM2Review(schedule: next, dueAt: due)
    }

    private static func passingInterval(after s: SM2Schedule) -> Int {
        let days: Int
        switch s.repetitions {
        case 0: days = 1
        case 1: days = 6
        default: days = Int((Double(max(s.intervalDays, 1)) * s.ease).rounded())
        }
        return min(maximumIntervalDays, max(1, days))
    }

    /// Next interval per button, shown under the grade buttons.
    public static func nextIntervals(for s: SM2Schedule,
                                     grades: [SM2Grade] = [.again, .hard, .good, .easy]) -> [SM2Grade: Int] {
        var out: [SM2Grade: Int] = [:]
        for g in grades { out[g] = review(s, grade: g, at: .distantPast).schedule.intervalDays }
        return out
    }

    /// Short interval for compact UI ("1d", "2mo", "1y").
    public static func intervalLabel(days: Int) -> String {
        if days < 30 { return "\(days)d" }
        if days < 365 { return "\(Int((Double(days) / 30).rounded()))mo" }
        return "\(Int((Double(days) / 365).rounded()))y"
    }
}

public struct StudyQueueItem: Sendable, Equatable {
    public var id: UUID
    public var dueAt: Date
    public var isNew: Bool

    public init(id: UUID, dueAt: Date, isNew: Bool) {
        self.id = id
        self.dueAt = dueAt
        self.isNew = isNew
    }
}

public enum StudyQueue {
    /// Due cards: reviewed ones first (oldest due first), then new ones. Ties break by id so the order is stable.
    public static func due(_ items: [StudyQueueItem], now: Date, limit: Int? = nil) -> [UUID] {
        let sorted = items.filter { $0.dueAt <= now }.sorted { a, b in
            if a.isNew != b.isNew { return !a.isNew }
            if a.dueAt != b.dueAt { return a.dueAt < b.dueAt }
            return a.id.uuidString < b.id.uuidString
        }
        let ids = sorted.map(\.id)
        guard let limit else { return ids }
        return Array(ids.prefix(max(0, limit)))
    }
}
