import Foundation
import Testing
@testable import SheafnoteCore

struct SM2SchedulerTests {
    let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    let fresh = SM2Schedule.initial
    let oneDay: TimeInterval = 86_400

    @Test func firstSuccessfulReviewIsOneDay() {
        let r = SM2Scheduler.review(fresh, grade: .good, at: now, calendar: utc)
        #expect(r.schedule.intervalDays == 1)
        #expect(r.schedule.repetitions == 1)
        #expect(r.dueAt == now.addingTimeInterval(oneDay))
    }

    @Test func secondSuccessfulReviewIsSixDays() {
        let first = SM2Scheduler.review(fresh, grade: .good, at: now).schedule
        let second = SM2Scheduler.review(first, grade: .good, at: now).schedule
        #expect(second.intervalDays == 6)
        #expect(second.repetitions == 2)
    }

    @Test func thirdReviewMultipliesByEase() {
        var s = fresh
        for _ in 0..<2 { s = SM2Scheduler.review(s, grade: .good, at: now).schedule }
        let third = SM2Scheduler.review(s, grade: .good, at: now).schedule
        #expect(third.intervalDays == Int((6.0 * s.ease).rounded()))
        #expect(third.repetitions == 3)
    }

    @Test func goodKeepsEaseEasyRaisesItHardLowersIt() {
        let good = SM2Scheduler.review(fresh, grade: .good, at: now).schedule.ease
        let easy = SM2Scheduler.review(fresh, grade: .easy, at: now).schedule.ease
        let hard = SM2Scheduler.review(fresh, grade: .hard, at: now).schedule.ease
        #expect(abs(good - 2.5) < 1e-9)
        #expect(abs(easy - 2.6) < 1e-9)
        #expect(hard < good)
    }

    @Test func failureResetsRepetitionsCountsLapseAndLowersEase() {
        var s = fresh
        for _ in 0..<3 { s = SM2Scheduler.review(s, grade: .good, at: now).schedule }
        let r = SM2Scheduler.review(s, grade: .again, at: now, calendar: utc)
        #expect(r.schedule.repetitions == 0)
        #expect(r.schedule.intervalDays == 1)
        #expect(r.schedule.lapses == 1)
        #expect(r.schedule.ease < s.ease)
        #expect(r.dueAt == now.addingTimeInterval(oneDay))
    }

    @Test func easeNeverDropsBelowFloor() {
        var s = fresh
        for _ in 0..<50 { s = SM2Scheduler.review(s, grade: .blackout, at: now).schedule }
        #expect(s.ease == SM2Scheduler.minimumEase)
        #expect(s.lapses == 50)
    }

    @Test func gradeZeroToFiveAllAccepted() {
        for raw in 0...5 {
            let r = SM2Scheduler.review(fresh, grade: SM2Grade(clamping: raw), at: now)
            #expect(r.schedule.ease >= SM2Scheduler.minimumEase)
            #expect(r.schedule.intervalDays >= 1)
        }
        #expect(SM2Grade(clamping: -3).rawValue == 0)
        #expect(SM2Grade(clamping: 99).rawValue == 5)
    }

    @Test func passingThresholdIsThree() {
        #expect(!SM2Grade(clamping: 2).isPassing)
        #expect(SM2Grade(clamping: 3).isPassing)
    }

    @Test func intervalIsCapped() {
        var s = SM2Schedule(ease: 3.0, intervalDays: 30_000, repetitions: 9, lapses: 0)
        s = SM2Scheduler.review(s, grade: .easy, at: now).schedule
        #expect(s.intervalDays == SM2Scheduler.maximumIntervalDays)
    }

    @Test func previewMatchesReview() {
        let preview = SM2Scheduler.nextIntervals(for: fresh)
        for grade in [SM2Grade.again, .hard, .good, .easy] {
            #expect(preview[grade] == SM2Scheduler.review(fresh, grade: grade, at: now).schedule.intervalDays)
        }
    }

    @Test func intervalLabelFormats() {
        #expect(SM2Scheduler.intervalLabel(days: 1) == "1d")
        #expect(SM2Scheduler.intervalLabel(days: 6) == "6d")
        #expect(SM2Scheduler.intervalLabel(days: 45) == "2mo")
        #expect(SM2Scheduler.intervalLabel(days: 400) == "1y")
    }

    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }
}

struct StudyQueueTests {
    let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    @Test func onlyDueCardsAreReturnedOldestFirst() {
        let a = UUID(), b = UUID(), c = UUID()
        let items = [
            StudyQueueItem(id: a, dueAt: now.addingTimeInterval(-100), isNew: false),
            StudyQueueItem(id: b, dueAt: now.addingTimeInterval(500), isNew: false),
            StudyQueueItem(id: c, dueAt: now.addingTimeInterval(-9_000), isNew: false),
        ]
        #expect(StudyQueue.due(items, now: now) == [c, a])
    }

    @Test func reviewedCardsComeBeforeNewOnesAndLimitApplies() {
        let new1 = UUID(), old1 = UUID(), old2 = UUID()
        let items = [
            StudyQueueItem(id: new1, dueAt: now.addingTimeInterval(-10_000), isNew: true),
            StudyQueueItem(id: old1, dueAt: now.addingTimeInterval(-10), isNew: false),
            StudyQueueItem(id: old2, dueAt: now.addingTimeInterval(-20), isNew: false),
        ]
        #expect(StudyQueue.due(items, now: now) == [old2, old1, new1])
        #expect(StudyQueue.due(items, now: now, limit: 2) == [old2, old1])
    }

    @Test func tiesAreBrokenByIDForDeterminism() {
        let ids = (0..<5).map { _ in UUID() }
        let items = ids.map { StudyQueueItem(id: $0, dueAt: now, isNew: false) }
        let out = StudyQueue.due(items.shuffled(), now: now)
        #expect(out == ids.sorted { $0.uuidString < $1.uuidString })
    }

    @Test func tenThousandCardsStayFast() {
        let items = (0..<10_000).map {
            StudyQueueItem(id: UUID(), dueAt: now.addingTimeInterval(Double($0 % 997) - 500), isNew: $0 % 7 == 0)
        }
        let start = Date()
        let out = StudyQueue.due(items, now: now, limit: 100)
        #expect(out.count == 100)
        #expect(Date().timeIntervalSince(start) < 1.0)
    }
}
