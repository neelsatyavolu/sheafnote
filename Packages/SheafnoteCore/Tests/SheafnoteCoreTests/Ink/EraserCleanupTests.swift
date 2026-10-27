import CoreGraphics
import Foundation
import Testing
@testable import SheafnoteCore

@Suite struct EraserCleanupTests {
    private func id(_ s: String) -> StrokeID { StrokeID(rawValue: s) }

    @Test func onlyStrokesTheEraseProducedAreCandidates() {
        let before: Set<StrokeID> = [id("a"), id("b"), id("c")]
        let after = [id("a"), id("b1"), id("b2"), id("c")]
        #expect(EraserCleanup.changedIndices(before: before, after: after) == [1, 2])
        #expect(EraserCleanup.changedIndices(before: before, after: Array(before).sorted()).isEmpty)
    }

    @Test func crumbsAreSmallNextToTheInkWidth() {
        #expect(EraserCleanup.isCrumb(visibleArea: 4, inkWidth: 2))       // a nub of a 2 pt pen line
        #expect(!EraserCleanup.isCrumb(visibleArea: 30, inkWidth: 2))     // 15 pt of that line is real ink
        #expect(EraserCleanup.isCrumb(visibleArea: 400, inkWidth: 20))    // highlighter sliver
        #expect(!EraserCleanup.isCrumb(visibleArea: 900, inkWidth: 20))
        #expect(EraserCleanup.isCrumb(visibleArea: 7, inkWidth: 0))       // floor for hairlines
        #expect(!EraserCleanup.isCrumb(visibleArea: 9, inkWidth: 0))
    }

    private func image(_ size: Int, fill rect: CGRect?, alpha: CGFloat = 1) throws -> CGImage {
        let ctx = try #require(CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                         space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        if let rect {
            ctx.setFillColor(CGColor(srgbRed: 0.1, green: 0.1, blue: 0.1, alpha: alpha))
            ctx.fill(rect)
        }
        return try #require(ctx.makeImage())
    }

    @Test func inkAreaSumsCoverageInPoints() throws {
        #expect(EraserCleanup.inkArea(of: try image(40, fill: nil), scale: 1) == 0)
        let square = try image(40, fill: CGRect(x: 5, y: 5, width: 10, height: 10))
        #expect(abs(EraserCleanup.inkArea(of: square, scale: 1) - 100) < 0.5)
        // The same 10 pt square rendered at 2× is 20 px across.
        let retina = try image(40, fill: CGRect(x: 5, y: 5, width: 20, height: 20))
        #expect(abs(EraserCleanup.inkArea(of: retina, scale: 2) - 100) < 0.5)
        let faint = try image(40, fill: CGRect(x: 0, y: 0, width: 10, height: 10), alpha: 0.5)
        #expect(abs(EraserCleanup.inkArea(of: faint, scale: 1) - 50) < 1)
    }
}
