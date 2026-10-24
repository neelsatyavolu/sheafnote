import CoreGraphics
import Testing
@testable import SheafnoteCore

@Suite("ZoomWindowModel")
struct ZoomWindowModelTests {
    /// Page 800x1000, magnification 4 gives a 200 wide focus; strip aspect 5 gives a 40 tall focus.
    private func make(magnification: CGFloat = 4) -> ZoomWindowModel {
        ZoomWindowModel(pageSize: CGSize(width: 800, height: 1000), magnification: magnification, stripAspect: 5,
                        leftMargin: 40, rightMargin: 40)
    }

    @Test func focusSizeFollowsMagnificationAndAspect() {
        #expect(make().focusSize == CGSize(width: 200, height: 40))
    }

    @Test func startsInsideThePageNearTheLeftMargin() {
        let model = make()
        #expect(model.focusOrigin.x >= 0)
        #expect(model.focusOrigin.y >= 0)
        #expect(abs(model.focusOrigin.x - max(0, 40 - 200 * model.keepFraction)) < 1e-9)
    }

    @Test func magnificationIsClamped() {
        var model = make()
        model.setMagnification(100)
        #expect(model.magnification == ZoomWindowModel.magnificationRange.upperBound)
        model.setMagnification(0)
        #expect(model.magnification == ZoomWindowModel.magnificationRange.lowerBound)
    }

    @Test func movingKeepsTheFocusInsideThePage() {
        var model = make()
        model.moveFocus(to: CGPoint(x: -50, y: -50))
        #expect(model.focusOrigin == .zero)
        model.moveFocus(to: CGPoint(x: 5000, y: 5000))
        #expect(model.focusOrigin == CGPoint(x: 600, y: 960))
        model.moveFocus(by: CGSize(width: -100, height: -100))
        #expect(model.focusOrigin == CGPoint(x: 500, y: 860))
    }

    @Test func stripPointsMapToPageCoordinates() {
        var model = make()
        model.moveFocus(to: CGPoint(x: 100, y: 300))
        let strip = CGSize(width: 500, height: 100)   // scale = 200 / 500 = 0.4
        #expect(model.pageLocation(forStrip: CGPoint(x: 250, y: 50), stripSize: strip) == CGPoint(x: 200, y: 320))
        #expect(abs(model.pageScale(forStrip: strip) - 0.4) < 1e-9)
    }

    @Test func degenerateStripSizeDoesNotCrash() {
        let model = make()
        #expect(model.pageScale(forStrip: .zero) == 1)
        #expect(model.pageLocation(forStrip: CGPoint(x: 5, y: 5), stripSize: .zero) == CGPoint(x: model.focusOrigin.x + 5, y: model.focusOrigin.y + 5))
    }

    @Test func advancesWhenThePenCrossesTheTrigger() {
        var model = make()
        model.triggerFraction = 0.8
        let strip = CGSize(width: 500, height: 100)
        #expect(!model.shouldAdvance(afterPenAtStrip: CGPoint(x: 350, y: 10), stripSize: strip))
        #expect(model.shouldAdvance(afterPenAtStrip: CGPoint(x: 400, y: 10), stripSize: strip))
    }

    @Test func autoAdvanceOffNeverAdvances() {
        var model = make()
        model.autoAdvance = false
        #expect(!model.shouldAdvance(afterPenAtStrip: CGPoint(x: 499, y: 0), stripSize: CGSize(width: 500, height: 100)))
    }

    @Test func advanceKeepsTheLastPenPositionNearTheLeftEdge() {
        var model = make()
        model.moveFocus(to: CGPoint(x: 100, y: 200))
        #expect(model.advance(keepingPageX: 270) == .movedRight)
        let expected = 270 - model.focusSize.width * model.keepFraction
        #expect(abs(model.focusOrigin.x - expected) < 1e-9)
        #expect(model.focusOrigin.y == 200)
    }

    @Test func advanceNeverMovesBackwards() {
        var model = make()
        model.moveFocus(to: CGPoint(x: 300, y: 200))
        _ = model.advance(keepingPageX: 100)
        #expect(model.focusOrigin.x >= 300)
    }

    @Test func advanceWrapsToTheNextLineAtTheRightMargin() {
        var model = make()
        model.moveFocus(to: CGPoint(x: 560, y: 200))
        #expect(model.advance(keepingPageX: 770) == .wrappedToNextLine)
        #expect(model.focusOrigin.y == 200 + model.lineStep)
        #expect(abs(model.focusOrigin.x - max(0, 40 - model.focusSize.width * model.keepFraction)) < 1e-9)
    }

    @Test func advanceStopsAtTheEndOfThePage() {
        var model = make()
        model.moveFocus(to: CGPoint(x: 560, y: 955))
        let before = model.focusOrigin
        #expect(model.advance(keepingPageX: 790) == .endOfPage)
        #expect(model.focusOrigin == before)
    }

    @Test func newLineMovesDownAndResetsToTheMargin() {
        var model = make()
        model.moveFocus(to: CGPoint(x: 400, y: 100))
        #expect(model.newLine() == .wrappedToNextLine)
        #expect(model.focusOrigin.y == 100 + model.lineStep)
        #expect(model.focusOrigin.x < 100)
    }

    @Test func marginsAreClampedToHalfThePage() {
        var model = make()
        model.leftMargin = 10_000
        model.normalizeMargins()
        #expect(model.leftMargin <= 400)
        model.rightMargin = -5
        model.normalizeMargins()
        #expect(model.rightMargin >= 0)
    }

    @Test func changingPageSizeReclampsTheFocus() {
        var model = make()
        model.moveFocus(to: CGPoint(x: 600, y: 960))
        model.setPageSize(CGSize(width: 400, height: 500))
        #expect(model.focusOrigin.x <= 400 - model.focusSize.width)
        #expect(model.focusOrigin.y <= 500 - model.focusSize.height)
    }

    @Test func focusRectMatchesOriginAndSize() {
        var model = make()
        model.moveFocus(to: CGPoint(x: 10, y: 20))
        #expect(model.focusRect == CGRect(x: 10, y: 20, width: 200, height: 40))
    }

    @Test func aspectChangeResizesTheFocusHeight() {
        var model = make()
        model.setStripAspect(10)
        #expect(model.focusSize == CGSize(width: 200, height: 20))
        model.setStripAspect(0)
        #expect(model.focusSize.height > 0)
    }
}
