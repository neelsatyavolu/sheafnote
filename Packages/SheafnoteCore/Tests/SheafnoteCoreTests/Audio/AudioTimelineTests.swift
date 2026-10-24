import CoreGraphics
import Foundation
import Testing
@testable import SheafnoteCore

struct AudioTimelineTests {
    let start = Date(timeIntervalSinceReferenceDate: 700_000_000)
    let page = UUID()

    func stroke(_ name: String, at offset: Double) -> TimedStroke {
        TimedStroke(id: StrokeID(rawValue: name), creationDate: start.addingTimeInterval(offset))
    }

    @Test func offsetComesFromCreationDate() {
        let t = AudioTimeline(startedAt: start, duration: 60)
        #expect(t.offset(for: stroke("a", at: 12.5)) == 12.5)
    }

    @Test func strokesOutsideTheRecordingHaveNoOffset() {
        let t = AudioTimeline(startedAt: start, duration: 60)
        #expect(t.offset(for: stroke("early", at: -30)) == nil)
        #expect(t.offset(for: stroke("late", at: 90)) == nil)
    }

    @Test func edgeJitterIsClamped() {
        let t = AudioTimeline(startedAt: start, duration: 60)
        #expect(t.offset(for: stroke("a", at: -0.3)) == 0)
        #expect(t.offset(for: stroke("b", at: 60.4)) == 60)
    }

    @Test func capturedMarkWinsOverCreationDate() {
        let s = stroke("a", at: 10)
        let t = AudioTimeline(startedAt: start, duration: 60,
                              marks: [AudioStrokeMark(pageID: page, strokeID: s.id, offset: 14)])
        #expect(t.offset(for: s) == 14)
    }

    @Test func strokesAfterPlayheadAreTheDimmedOnes() {
        let t = AudioTimeline(startedAt: start, duration: 60)
        let strokes = [stroke("before", at: -100), stroke("a", at: 5), stroke("b", at: 20), stroke("c", at: 50)]
        let dimmed = t.strokesAfter(playhead: 20, among: strokes)
        #expect(dimmed == [StrokeID(rawValue: "c")])
        #expect(t.strokesAfter(playhead: 0, among: strokes).count == 3)
        #expect(t.strokesAfter(playhead: 60, among: strokes).isEmpty)
    }

    @Test func addingNeverReplacesAnExistingMark() {
        let id = StrokeID(rawValue: "a")
        let t = AudioTimeline(startedAt: start, duration: 0)
            .adding(AudioStrokeMark(pageID: page, strokeID: id, offset: 3))
            .adding(AudioStrokeMark(pageID: page, strokeID: id, offset: 9))
        #expect(t.marks.count == 1)
        #expect(t.marks[0].offset == 3)
    }

    @Test func finishedClampsMarksToTheFinalDuration() {
        let t = AudioTimeline(startedAt: start, duration: 0)
            .adding(AudioStrokeMark(pageID: page, strokeID: StrokeID(rawValue: "a"), offset: 12))
            .finished(duration: 10)
        #expect(t.duration == 10)
        #expect(t.marks[0].offset == 10)
    }

    @Test func marksRoundTripThroughJSON() {
        let t = AudioTimeline(startedAt: start, duration: 30,
                              marks: [AudioStrokeMark(pageID: page, strokeID: StrokeID(rawValue: "x"), offset: 4.25)])
        let back = AudioTimeline(startedAt: start, duration: 30, encodedMarks: t.encodedMarks)
        #expect(back == t)
        #expect(AudioTimeline(startedAt: start, duration: 1, encodedMarks: Data()).marks.isEmpty)
    }
}

struct StrokeSeekHitTestTests {
    let a = (id: StrokeID(rawValue: "a"), points: [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0)])
    let b = (id: StrokeID(rawValue: "b"), points: [CGPoint(x: 0, y: 30), CGPoint(x: 100, y: 30)])

    @Test func picksTheNearestStrokeWithinTolerance() {
        #expect(StrokeSeekHitTest.nearest(to: CGPoint(x: 50, y: 6), among: [a, b], tolerance: 10) == a.id)
        #expect(StrokeSeekHitTest.nearest(to: CGPoint(x: 50, y: 24), among: [a, b], tolerance: 10) == b.id)
    }

    @Test func missesWhenNothingIsWithinTolerance() {
        #expect(StrokeSeekHitTest.nearest(to: CGPoint(x: 50, y: 15), among: [a, b], tolerance: 10) == nil)
    }

    @Test func usesSegmentsNotJustSamplePoints() {
        #expect(StrokeSeekHitTest.nearest(to: CGPoint(x: 50, y: 2), among: [a], tolerance: 3) == a.id)
    }

    @Test func handlesSinglePointAndEmptyStrokes() {
        let dot = (id: StrokeID(rawValue: "dot"), points: [CGPoint(x: 5, y: 5)])
        let empty = (id: StrokeID(rawValue: "e"), points: [CGPoint]())
        #expect(StrokeSeekHitTest.nearest(to: CGPoint(x: 6, y: 6), among: [dot, empty], tolerance: 3) == dot.id)
        #expect(StrokeSeekHitTest.nearest(to: .zero, among: [empty], tolerance: 100) == nil)
    }
}
