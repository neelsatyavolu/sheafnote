import PencilKit
import SwiftUI
import Testing
import UIKit
import SheafnoteCore
@testable import Sheafnote

@MainActor
@Suite struct SnappedStrokeTests {
    @Test func replacementKeepsInkColourAndDateAndLiesOnTheFigure() throws {
        let original = InkSketch.stroke(points: InkSketch.circle(center: CGPoint(x: 200, y: 200), radius: 60, wobble: 5), type: .fountainPen,
                                        color: .systemBlue, width: 4, date: Date(timeIntervalSinceReferenceDate: 777))
        let figure = ShapeFigure.ellipse(center: CGPoint(x: 200, y: 200), radii: CGSize(width: 60, height: 60), rotation: 0)
        let snapped = SnappedStroke.make(replacing: original, with: figure)
        #expect(snapped.ink.inkType == .fountainPen && snapped.ink.color == original.ink.color)
        #expect(snapped.path.creationDate == original.path.creationDate)
        #expect(snapped.path.count > 100)
        for point in snapped.path { #expect(abs(hypot(point.location.x - 200, point.location.y - 200) - 60) < 0.01) }
        #expect(abs(snapped.path[0].size.width - 4) < 0.01)
    }

    @Test func strokesWithATransformAreSnappedInPageSpace() throws {
        var original = InkSketch.line(CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 3))
        original.transform = CGAffineTransform(translationX: 50, y: 70).scaledBy(x: 2, y: 2)
        let snapped = SnappedStroke.line(replacing: original, from: CGPoint(x: 50, y: 70), to: CGPoint(x: 250, y: 70))
        #expect(snapped.transform == original.transform)
        let first = snapped.path[0].location.applying(snapped.transform)
        let lastPoint = try #require(snapped.path.last)
        let last = lastPoint.location.applying(snapped.transform)
        #expect(abs(first.x - 50) < 0.01 && abs(first.y - 70) < 0.01 && abs(last.x - 250) < 0.01 && abs(last.y - 70) < 0.01)
    }

    @Test func tooFewPointsLeaveTheStrokeAlone() {
        let original = InkSketch.line(CGPoint(x: 0, y: 0), CGPoint(x: 50, y: 0))
        #expect(SnappedStroke.make(replacing: original, pagePoints: [CGPoint(x: 1, y: 1)]).path.count == original.path.count)
    }

    @Test func freehandStrokeNeedsTwoPoints() {
        #expect(FreehandStroke.make(points: [.zero], colorHex: "#FF0000", width: 3) == nil)
        let stroke = FreehandStroke.make(points: [.zero, CGPoint(x: 10, y: 10)], colorHex: "#FF0000", width: 5)
        #expect(stroke?.ink.color.hexString == "#FF0000" && stroke?.path.first?.size.width == 5)
    }
}

@MainActor
@Suite struct InkSnapperTests {
    @Test func givesUpQuietlyWhenNoNewStrokeAppears() async throws {
        let f = try InkToolsFixture()
        let page = try f.page()
        let replaced = await InkSnapper.replaceLastStroke(on: page, baseline: 0, name: "Test") { $0 }
        #expect(!replaced && page.drawing.strokes.isEmpty)
    }

    @Test func leavesInkAloneWhenMoreThanOneStrokeArrived() async throws {
        let f = try InkToolsFixture()
        let page = try f.page()
        page.setDrawing(PKDrawing(strokes: [InkSketch.line(.zero, CGPoint(x: 50, y: 0)), InkSketch.line(CGPoint(x: 0, y: 20), CGPoint(x: 50, y: 20))]),
                        undoName: "Draw")
        let before = page.drawing.dataRepresentation()
        let replaced = await InkSnapper.replaceLastStroke(on: page, baseline: 0, name: "Test") { _ in InkSketch.line(.zero, CGPoint(x: 9, y: 9)) }
        #expect(!replaced && page.drawing.dataRepresentation() == before)
    }
}

@MainActor
@Suite struct DrawAndHoldTests {
    /// Feeds a stroke the way the canvas host does, with timestamps measured back from now so the pen has "held".
    func draw(_ path: [CGPoint], holdFor hold: TimeInterval, on page: PageSession, f: InkToolsFixture,
              observer: DrawAndHoldObserver, canvasStroke: PKStroke) async {
        let end = DrawAndHoldObserver.now
        let moveTime = hold + 0.4
        let step = moveTime / Double(max(path.count, 1))
        let start = end - hold - moveTime
        observer.strokeBegan(InkSketch.sample(path[0], at: start), page: page, editor: f.session)
        for (i, p) in path.enumerated().dropFirst() {
            observer.strokeMoved([InkSketch.sample(p, at: start + step * Double(i))], page: page, editor: f.session)
        }
        let last = path[path.count - 1]
        for k in 1...4 {
            let jitter = CGPoint(x: last.x + CGFloat(k % 2), y: last.y)
            observer.strokeMoved([InkSketch.sample(jitter, at: end - hold + hold * Double(k) / 5)], page: page, editor: f.session)
        }
        // PencilKit adds the finished stroke a moment after the pen lifts.
        observer.strokeEnded(InkSketch.sample(last, at: end), page: page, editor: f.session)
        page.setDrawing(PKDrawing(strokes: [canvasStroke]), undoName: "Draw")
        try? await Task.sleep(for: .milliseconds(150))
    }

    @Test func holdingAtTheEndOfACircleSnapsItToAPerfectOne() async throws {
        let f = try InkToolsFixture()
        let page = try f.page()
        let observer = DrawAndHoldObserver(settings: f.settings)
        let wobbly = InkSketch.circle(center: CGPoint(x: 300, y: 300), radius: 80, wobble: 4)
        await draw(wobbly, holdFor: 0.9, on: page, f: f, observer: observer, canvasStroke: InkSketch.stroke(points: wobbly, width: 5))
        #expect(page.drawing.strokes.count == 1)
        let center = CGPoint(x: 300, y: 300)
        let radii = page.drawing.strokes[0].path.map { hypot($0.location.x - center.x, $0.location.y - center.y) }
        #expect((radii.max() ?? 0) - (radii.min() ?? 0) < 6, "the wobble is gone: \(radii.min() ?? 0)...\(radii.max() ?? 0)")
        #expect(abs((radii.reduce(0, +) / CGFloat(radii.count)) - 80) < 6)
    }

    @Test func undoBringsTheHandDrawnStrokeBack() async throws {
        let f = try InkToolsFixture()
        let page = try f.page()
        let observer = DrawAndHoldObserver(settings: f.settings)
        let wobbly = InkSketch.circle(center: CGPoint(x: 300, y: 300), radius: 80, wobble: 4)
        let hand = InkSketch.stroke(points: wobbly, width: 5)
        await draw(wobbly, holdFor: 0.9, on: page, f: f, observer: observer, canvasStroke: hand)
        let snappedCount = page.drawing.strokes[0].path.count
        await InkToolsFixture.settle()
        f.session.undo()
        #expect(page.drawing.strokes.count == 1 && page.drawing.strokes[0].path.count == hand.path.count && snappedCount != hand.path.count)
    }

    @Test func noHoldLeavesTheStrokeAlone() async throws {
        let f = try InkToolsFixture()
        let page = try f.page()
        let observer = DrawAndHoldObserver(settings: f.settings)
        let wobbly = InkSketch.circle(center: CGPoint(x: 300, y: 300), radius: 80, wobble: 4)
        let hand = InkSketch.stroke(points: wobbly, width: 5)
        await draw(wobbly, holdFor: 0.1, on: page, f: f, observer: observer, canvasStroke: hand)
        #expect(page.drawing.strokes[0].path.count == hand.path.count)
    }

    @Test func aHeldScribbleStaysAsDrawn() async throws {
        let f = try InkToolsFixture()
        let page = try f.page()
        let observer = DrawAndHoldObserver(settings: f.settings)
        let walk = InkSketch.randomWalk()
        let hand = InkSketch.stroke(points: walk)
        await draw(walk, holdFor: 0.9, on: page, f: f, observer: observer, canvasStroke: hand)
        #expect(page.drawing.strokes[0].path.count == hand.path.count)
    }

    @Test func theSettingTurnsItOff() async throws {
        let f = try InkToolsFixture()
        f.settings.setDrawAndHold(false)
        let page = try f.page()
        let observer = DrawAndHoldObserver(settings: f.settings)
        let wobbly = InkSketch.circle(center: CGPoint(x: 300, y: 300), radius: 80, wobble: 4)
        let hand = InkSketch.stroke(points: wobbly, width: 5)
        await draw(wobbly, holdFor: 0.9, on: page, f: f, observer: observer, canvasStroke: hand)
        #expect(page.drawing.strokes[0].path.count == hand.path.count)
    }

    @Test func aCancelledStrokeNeverSnaps() async throws {
        let f = try InkToolsFixture()
        let page = try f.page()
        let observer = DrawAndHoldObserver(settings: f.settings)
        let now = DrawAndHoldObserver.now
        observer.strokeBegan(InkSketch.sample(CGPoint(x: 10, y: 10), at: now - 2), page: page, editor: f.session)
        observer.strokeCancelled(page: page, editor: f.session)
        observer.strokeEnded(InkSketch.sample(CGPoint(x: 10, y: 10), at: now), page: page, editor: f.session)
        page.setDrawing(PKDrawing(strokes: [InkSketch.line(.zero, CGPoint(x: 80, y: 80))]), undoName: "Draw")
        try? await Task.sleep(for: .milliseconds(100))
        #expect(page.drawing.strokes[0].path.count == InkSketch.line(.zero, CGPoint(x: 80, y: 80)).path.count)
    }

    @Test func itWatchesThePenOnly() throws {
        let f = try InkToolsFixture()
        #expect(DrawAndHoldObserver(settings: f.settings).activeToolIDs == [.pen])
        #expect(StraightHighlighterObserver(settings: f.settings).activeToolIDs == [.highlighter])
    }
}

@MainActor
@Suite struct StraightHighlighterTests {
    func highlight(from a: CGPoint, to b: CGPoint, f: InkToolsFixture, page: PageSession, observer: StraightHighlighterObserver) async {
        observer.strokeBegan(InkSketch.sample(a, at: 1), page: page, editor: f.session)
        observer.strokeEnded(InkSketch.sample(b, at: 2), page: page, editor: f.session)
        let wobbly = InkSketch.samples([a, CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 + 12), b], step: 4)
        page.setDrawing(PKDrawing(strokes: [InkSketch.stroke(points: wobbly, type: .marker, color: .yellow, width: 18)]), undoName: "Draw")
        try? await Task.sleep(for: .milliseconds(150))
    }

    @Test func withTheOptionOnTheStrokeBecomesAStraightLine() async throws {
        let f = try InkToolsFixture()
        f.settings.setStraightHighlighter(true)
        let page = try f.page()
        await highlight(from: CGPoint(x: 100, y: 200), to: CGPoint(x: 400, y: 207), f: f, page: page,
                        observer: StraightHighlighterObserver(settings: f.settings))
        let stroke = page.drawing.strokes[0]
        #expect(stroke.ink.inkType == .marker && stroke.ink.color.hexString == UIColor.yellow.hexString)
        let ys = Set(stroke.path.map { Int($0.location.y.rounded()) })
        #expect(ys.count == 1, "snapped exactly horizontal")
        #expect(abs((stroke.path.last?.location.x ?? 0) - (stroke.path.first?.location.x ?? 0)) > 290)
        #expect(Float(stroke.path.first?.size.width ?? 0) == 18)
    }

    @Test func withTheOptionOffTheStrokeIsUntouched() async throws {
        let f = try InkToolsFixture()
        let page = try f.page()
        await highlight(from: CGPoint(x: 100, y: 200), to: CGPoint(x: 400, y: 207), f: f, page: page,
                        observer: StraightHighlighterObserver(settings: f.settings))
        #expect(Set(page.drawing.strokes[0].path.map { Int($0.location.y.rounded()) }).count > 1)
    }

    @Test func aDiagonalLineKeepsItsAngle() async throws {
        let f = try InkToolsFixture()
        f.settings.setStraightHighlighter(true)
        let page = try f.page()
        await highlight(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 300, y: 250), f: f, page: page,
                        observer: StraightHighlighterObserver(settings: f.settings))
        let stroke = page.drawing.strokes[0]
        let firstPoint = try #require(stroke.path.first), lastPoint = try #require(stroke.path.last)
        let a = firstPoint.location, b = lastPoint.location
        #expect(abs(a.x - 100) < 0.01 && abs(b.y - 250) < 0.01)
        for p in stroke.path { #expect(abs((p.location.y - a.y) / (p.location.x - a.x + 0.0001) - 0.75) < 0.05 || p.location == a) }
    }

    @Test func aTapIsNotALine() async throws {
        let f = try InkToolsFixture()
        f.settings.setStraightHighlighter(true)
        let page = try f.page()
        let observer = StraightHighlighterObserver(settings: f.settings)
        observer.strokeBegan(InkSketch.sample(CGPoint(x: 100, y: 100), at: 1), page: page, editor: f.session)
        observer.strokeEnded(InkSketch.sample(CGPoint(x: 103, y: 101), at: 1.1), page: page, editor: f.session)
        let dot = InkSketch.stroke(points: [CGPoint(x: 100, y: 100), CGPoint(x: 103, y: 101)], type: .marker, width: 18)
        page.setDrawing(PKDrawing(strokes: [dot]), undoName: "Draw")
        try? await Task.sleep(for: .milliseconds(100))
        #expect(page.drawing.strokes[0].path.count == dot.path.count)
    }
}
