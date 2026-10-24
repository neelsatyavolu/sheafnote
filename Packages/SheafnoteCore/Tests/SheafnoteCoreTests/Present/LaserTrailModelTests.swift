import CoreGraphics
import Testing
@testable import SheafnoteCore

@Suite("LaserTrailModel")
struct LaserTrailModelTests {
    @Test func startsEmpty() {
        let model = LaserTrailModel()
        #expect(model.isEmpty)
        #expect(model.head == nil)
        #expect(model.visiblePoints(at: 0).isEmpty)
    }

    @Test func headFollowsLatestPointWhileDown() {
        var model = LaserTrailModel()
        model.begin(at: CGPoint(x: 1, y: 2), time: 0)
        model.move(to: CGPoint(x: 5, y: 6), time: 0.1)
        #expect(model.head == CGPoint(x: 5, y: 6))
        #expect(model.isDown)
    }

    @Test func liftingRemovesTheHeadButKeepsTheFadingTrail() {
        var model = LaserTrailModel()
        model.begin(at: .zero, time: 0)
        model.move(to: CGPoint(x: 10, y: 0), time: 0.1)
        model.end(time: 0.2)
        #expect(model.head == nil)
        #expect(!model.isDown)
        #expect(model.visiblePoints(at: 0.3).count == 2)
    }

    @Test func opacityDecaysLinearlyToZero() {
        var model = LaserTrailModel(fadeDuration: 1)
        model.begin(at: .zero, time: 0)
        #expect(model.opacity(ofPointAt: 0, now: 0) == 1)
        #expect(abs(model.opacity(ofPointAt: 0, now: 0.25) - 0.75) < 1e-9)
        #expect(model.opacity(ofPointAt: 0, now: 1) == 0)
        #expect(model.opacity(ofPointAt: 0, now: 5) == 0)
    }

    @Test func fullyFadedPointsAreNotVisible() {
        var model = LaserTrailModel(fadeDuration: 1)
        model.begin(at: .zero, time: 0)
        model.move(to: CGPoint(x: 1, y: 0), time: 0.9)
        model.end(time: 0.9)
        let visible = model.visiblePoints(at: 1.5)
        #expect(visible.count == 1)
        #expect(visible[0].location == CGPoint(x: 1, y: 0))
    }

    @Test func pointCountIsCapped() {
        var model = LaserTrailModel(maxPoints: 10)
        model.begin(at: .zero, time: 0)
        for i in 1...50 { model.move(to: CGPoint(x: CGFloat(i), y: 0), time: Double(i) * 0.001) }
        #expect(model.points.count == 10)
        #expect(model.points.last?.location.x == 50)
    }

    @Test func pruneDropsExpiredPoints() {
        var model = LaserTrailModel(fadeDuration: 1)
        model.begin(at: .zero, time: 0)
        model.move(to: CGPoint(x: 1, y: 0), time: 2)
        model.prune(now: 2.5)
        #expect(model.points.count == 1)
    }

    @Test func dotStyleShowsOnlyTheHead() {
        var model = LaserTrailModel(style: .dot)
        model.begin(at: .zero, time: 0)
        model.move(to: CGPoint(x: 4, y: 4), time: 0.1)
        let visible = model.visiblePoints(at: 0.1)
        #expect(visible.count == 1)
        #expect(visible[0].opacity == 1)
        model.end(time: 0.2)
        #expect(model.visiblePoints(at: 0.2).isEmpty)
    }

    @Test func isFadedOutOnceEverythingExpired() {
        var model = LaserTrailModel(fadeDuration: 1)
        model.begin(at: .zero, time: 0)
        #expect(!model.isFadedOut(at: 0.5))
        model.end(time: 0.5)
        #expect(!model.isFadedOut(at: 1.2))
        #expect(model.isFadedOut(at: 1.6))
    }

    @Test func fadeDurationIsClampedToAUsableRange() {
        #expect(LaserTrailModel(fadeDuration: 0).fadeDuration >= 0.1)
        #expect(LaserTrailModel(fadeDuration: 99).fadeDuration <= 5)
    }

    @Test func clearEmptiesEverything() {
        var model = LaserTrailModel()
        model.begin(at: .zero, time: 0)
        model.clear()
        #expect(model.isEmpty)
        #expect(!model.isDown)
    }
}
