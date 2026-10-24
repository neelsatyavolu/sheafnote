import CoreGraphics
import Testing
@testable import SheafnoteCore

struct FlashcardRegionsTests {
    let page = CGSize(width: 600, height: 800)

    @Test func clampKeepsRectInsidePage() {
        let r = CardRegions.clamp(CGRect(x: -20, y: 790, width: 100, height: 100), to: page)
        #expect(r.minX >= 0 && r.minY >= 0 && r.maxX <= 600 && r.maxY <= 800)
        #expect(r.size == CGSize(width: 100, height: 100))
    }

    @Test func clampEnforcesMinimumAndMaximumSize() {
        let tiny = CardRegions.clamp(CGRect(x: 10, y: 10, width: 2, height: 2), to: page)
        #expect(tiny.width == CardRegions.minimumSide && tiny.height == CardRegions.minimumSide)
        let huge = CardRegions.clamp(CGRect(x: 0, y: 0, width: 5000, height: 5000), to: page)
        #expect(huge.size == page)
    }

    @Test func selectionBecomesFrontAndBackIsBelow() {
        let regions = CardRegions.initial(forSelection: CGRect(x: 100, y: 100, width: 200, height: 60), in: page)
        #expect(regions.back.minY > regions.front.maxY)
        #expect(regions.back.size == regions.front.size)
        #expect(regions.front.contains(CGRect(x: 100, y: 100, width: 200, height: 60)))
    }

    @Test func backGoesAboveWhenSelectionIsAtTheBottom() {
        let regions = CardRegions.initial(forSelection: CGRect(x: 100, y: 700, width: 200, height: 80), in: page)
        #expect(regions.back.maxY < regions.front.minY)
    }

    @Test func defaultRegionsAreInsideThePageAndDoNotOverlap() {
        let r = CardRegions.initial(in: page)
        #expect(CGRect(origin: .zero, size: page).contains(r.front))
        #expect(CGRect(origin: .zero, size: page).contains(r.back))
        #expect(!r.front.intersects(r.back))
    }

    @Test func clampedAppliesToBoth() {
        let r = CardRegions(front: CGRect(x: -5, y: -5, width: 10, height: 10), back: CGRect(x: 900, y: 900, width: 50, height: 50))
        let c = r.clamped(to: page)
        #expect(c.front.minX == 0 && c.back.maxX <= 600)
    }
}
