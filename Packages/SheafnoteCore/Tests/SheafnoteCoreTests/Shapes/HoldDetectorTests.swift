import CoreGraphics
import Foundation
import Testing
@testable import SheafnoteCore

@Suite struct HoldDetectorTests {
    @Test func notHeldBeforeTheDuration() {
        var d = HoldDetector()
        d.begin(at: CGPoint(x: 10, y: 10), time: 100)
        #expect(!d.isHeld(at: 100.3))
        #expect(d.isHeld(at: 100.6))
    }

    @Test func smallJitterKeepsTheHold() {
        var d = HoldDetector()
        d.begin(at: CGPoint(x: 10, y: 10), time: 0)
        d.move(to: CGPoint(x: 11, y: 10.5), time: 0.2)
        d.move(to: CGPoint(x: 9.5, y: 9.5), time: 0.4)
        #expect(d.isHeld(at: 0.65))
    }

    @Test func movementRestartsTheHold() {
        var d = HoldDetector()
        d.begin(at: .zero, time: 0)
        d.move(to: CGPoint(x: 30, y: 0), time: 0.5)
        #expect(!d.isHeld(at: 0.7))
        #expect(d.isHeld(at: 1.1))
    }

    @Test func slowCreepIsMeasuredFromTheAnchorNotTheLastSample() {
        var d = HoldDetector()
        d.begin(at: .zero, time: 0)
        for i in 1...6 { d.move(to: CGPoint(x: CGFloat(i) * 0.9, y: 0), time: Double(i) * 0.1) }
        // 5.4 points from the start: the pen moved, so the clock restarted when the tolerance was passed.
        #expect(!d.isHeld(at: 0.7))
    }

    @Test func remainingCountsDown() {
        var d = HoldDetector()
        #expect(d.remaining(at: 0) == nil && !d.isTracking)
        d.begin(at: .zero, time: 10)
        #expect(abs((d.remaining(at: 10.2) ?? 0) - 0.4) < 0.0001)
        #expect(d.remaining(at: 12) == 0)
        d.reset()
        #expect(!d.isTracking && !d.isHeld(at: 20))
    }

    @Test func moveBeforeBeginStartsTracking() {
        var d = HoldDetector()
        d.move(to: CGPoint(x: 5, y: 5), time: 1)
        #expect(d.isTracking && d.isHeld(at: 1.7))
    }
}
