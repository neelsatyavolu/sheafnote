import CoreGraphics
import Testing
@testable import SheafnoteCore

@Suite("AspectFit")
struct AspectFitTests {
    @Test func portraitPageIsPillarboxedInALandscapeScreen() {
        let fit = AspectFit(content: CGSize(width: 600, height: 800), in: CGSize(width: 1600, height: 800))
        #expect(fit.rect == CGRect(x: 500, y: 0, width: 600, height: 800))
        #expect(fit.scale == 1)
    }

    @Test func wideContentIsLetterboxed() {
        let fit = AspectFit(content: CGSize(width: 800, height: 400), in: CGSize(width: 400, height: 400))
        #expect(fit.rect == CGRect(x: 0, y: 100, width: 400, height: 200))
        #expect(fit.scale == 0.5)
    }

    @Test func pointsRoundTrip() throws {
        let fit = AspectFit(content: CGSize(width: 600, height: 800), in: CGSize(width: 1200, height: 800))
        let view = fit.viewPoint(forPage: CGPoint(x: 300, y: 400))
        #expect(view == CGPoint(x: 600, y: 400))
        #expect(try #require(fit.pagePoint(forView: view)) == CGPoint(x: 300, y: 400))
    }

    @Test func pointsOutsideThePageMapToNil() {
        let fit = AspectFit(content: CGSize(width: 600, height: 800), in: CGSize(width: 1200, height: 800))
        #expect(fit.pagePoint(forView: CGPoint(x: 10, y: 10)) == nil)
    }

    @Test func emptySizesGiveAnEmptyRect() {
        #expect(AspectFit(content: .zero, in: CGSize(width: 10, height: 10)).rect == .zero)
        #expect(AspectFit(content: CGSize(width: 10, height: 10), in: .zero).rect == .zero)
        #expect(AspectFit(content: .zero, in: .zero).scale == 0)
    }
}
