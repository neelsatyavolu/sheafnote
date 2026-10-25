import CoreGraphics
import Foundation
import Testing
@testable import SheafnoteCore

@Suite struct FoldSpreadTests {
    let a4 = CGSize(width: 595, height: 842)

    @Test func gutterCoversFoldAtWidthFit() throws {
        let viewport = CGSize(width: 951, height: 669)
        let gutter = try #require(FoldSpread.gutter(columnWidth: 615, spreadHeight: nil, viewport: viewport, foldWidth: 40))
        let fit = viewport.width / (2 * 615 + gutter)
        #expect(abs(fit * gutter - 40) < 0.001)
    }

    @Test func gutterCoversFoldWhenHeightLimitsTheFit() throws {
        // A tall spread in a wide viewport: the height decides the zoom, so the gutter must grow to still cover the fold.
        let viewport = CGSize(width: 951, height: 400)
        let gutter = try #require(FoldSpread.gutter(columnWidth: 615, spreadHeight: 882, viewport: viewport, foldWidth: 40))
        let fit = min(viewport.width / (2 * 615 + gutter), viewport.height / 882)
        #expect(fit * gutter >= 40 - 0.001)
        #expect(abs(fit * gutter - 40) < 0.001)
    }

    @Test func noGutterForAFoldThatLeavesNoRoom() {
        let viewport = CGSize(width: 400, height: 600)
        #expect(FoldSpread.gutter(columnWidth: 615, spreadHeight: nil, viewport: viewport, foldWidth: 200) == nil)
        #expect(FoldSpread.gutter(columnWidth: 615, spreadHeight: nil, viewport: viewport, foldWidth: 0) == nil)
        #expect(FoldSpread.gutter(columnWidth: 0, spreadHeight: nil, viewport: viewport, foldWidth: 20) == nil)
    }

    @Test func verticalPairsFacePagesAcrossTheGutter() {
        let result = FoldSpread.layout(sizes: [a4, a4, a4], gutter: 30, margin: 20, spacing: 20, horizontal: false)
        let frames = result.slots.map(\.frame)
        #expect(frames[0] == CGRect(x: 20, y: 20, width: 595, height: 842))
        #expect(frames[1] == CGRect(x: 20 + 595 + 30, y: 20, width: 595, height: 842))
        // The lone last page takes the left column of the next spread.
        #expect(frames[2] == CGRect(x: 20, y: 20 + 842 + 20, width: 595, height: 842))
        #expect(result.slots[0].spread == result.slots[1].spread)
        #expect(result.slots[0].spread == CGRect(x: 20, y: 20, width: 2 * 595 + 30, height: 842))
        #expect(result.contentSize == CGSize(width: 2 * 20 + 2 * 595 + 30, height: 2 * 842 + 20 + 2 * 20))
    }

    @Test func verticalGutterSitsAtTheContentCenter() {
        let result = FoldSpread.layout(sizes: [a4, a4], gutter: 30, margin: 20, spacing: 20, horizontal: false)
        let gapCenter = (result.slots[0].frame.maxX + result.slots[1].frame.minX) / 2
        #expect(gapCenter == result.contentSize.width / 2)
    }

    @Test func narrowerPagesCenterInTheirColumn() {
        let small = CGSize(width: 395, height: 500)
        let result = FoldSpread.layout(sizes: [a4, small], gutter: 30, margin: 20, spacing: 20, horizontal: false)
        #expect(result.slots[1].frame == CGRect(x: 20 + 595 + 30 + 100, y: 20 + 171, width: 395, height: 500))
    }

    @Test func horizontalSpreadsRunLeftToRight() {
        let result = FoldSpread.layout(sizes: [a4, a4, a4, a4], gutter: 30, margin: 20, spacing: 20, horizontal: true)
        let spreads = result.slots.map(\.spread)
        #expect(spreads[0] == spreads[1])
        #expect(spreads[2] == spreads[3])
        #expect(spreads[2].minX == spreads[0].maxX + 20)
        #expect(result.slots[2].frame.minX == spreads[2].minX)
        #expect(result.contentSize == CGSize(width: spreads[3].maxX + 20, height: 842 + 2 * 20))
    }

    @Test func gridColumnsStayEvenAcrossAFold() {
        // 3 columns of 150 fit in 520 with 20 spacing; dropping to 2 keeps the fold between columns.
        #expect(FoldSpread.evenColumnCount(width: 520, minimum: 150, spacing: 20) == 2)
        #expect(FoldSpread.evenColumnCount(width: 700, minimum: 150, spacing: 20) == 4)
        #expect(FoldSpread.evenColumnCount(width: 200, minimum: 150, spacing: 20) == 1)
        #expect(FoldSpread.evenColumnCount(width: 0, minimum: 150, spacing: 20) == 1)
    }

    @Test func emptyLayout() {
        let result = FoldSpread.layout(sizes: [], gutter: 30, margin: 20, spacing: 20, horizontal: false)
        #expect(result.slots.isEmpty)
        #expect(result.contentSize == .zero)
    }
}
