import PencilKit
import Testing
import SheafnoteCore
@testable import Sheafnote

@Suite struct LayoutAndGeometryTests {
    private func pages(_ n: Int, size: CGSize = CGSize(width: 600, height: 800)) -> [(id: UUID, size: CGSize)] {
        (0..<n).map { _ in (UUID(), size) }
    }

    @Test func verticalLayoutStacksCenteredPages() {
        let list = [(id: UUID(), size: CGSize(width: 600, height: 800)), (id: UUID(), size: CGSize(width: 400, height: 500))]
        let layout = PageLayoutEngine.layout(pages: list, direction: .vertical)
        #expect(layout.contentSize.width == 640)
        let first = layout.entries[0].frame, second = layout.entries[1].frame
        #expect(first.minX == 20 && first.minY == 20)
        #expect(second.minY == first.maxY + PageLayoutEngine.spacing)
        #expect(second.midX == layout.contentSize.width / 2)
        #expect(layout.contentSize.height == second.maxY + PageLayoutEngine.margin)
    }

    @Test func horizontalLayoutPlacesPagesSideBySide() {
        let list = pages(3)
        let layout = PageLayoutEngine.layout(pages: list, direction: .horizontal)
        let frames = layout.entries.map(\.frame)
        #expect(frames[1].minX == frames[0].maxX + PageLayoutEngine.spacing)
        #expect(layout.contentSize.height == 840)
        #expect(frames.allSatisfy { $0.midY == 420 })
    }

    @Test func emptyLayoutIsEmpty() {
        let layout = PageLayoutEngine.layout(pages: [], direction: .vertical)
        #expect(layout.entries.isEmpty && layout.contentSize == .zero)
        #expect(layout.currentPage(visibleRect: .zero) == nil)
    }

    @Test(arguments: [ScrollDirection.vertical, .horizontal])
    func intersectionMatchesBruteForce(direction: ScrollDirection) {
        let layout = PageLayoutEngine.layout(pages: pages(200), direction: direction)
        for offset in stride(from: CGFloat(-50), to: 90_000, by: 3_333) {
            let rect = direction == .vertical ? CGRect(x: 0, y: offset, width: 700, height: 1_500)
                                              : CGRect(x: offset, y: 0, width: 1_500, height: 900)
            let fast = layout.pages(intersecting: rect)
            let slow = layout.entries.filter { $0.frame.intersects(rect) }.map(\.id)
            #expect(fast == slow)
        }
    }

    @Test func currentPageIsTheOneUnderTheCenter() {
        let layout = PageLayoutEngine.layout(pages: pages(5), direction: .vertical)
        let target = layout.entries[3]
        let visible = CGRect(x: 0, y: target.frame.midY - 300, width: 640, height: 600)
        #expect(layout.currentPage(visibleRect: visible) == target.id)
        // In a gap between pages the nearest one wins.
        let gap = CGRect(x: 0, y: layout.entries[1].frame.maxY + 5, width: 640, height: 2)
        #expect(layout.currentPage(visibleRect: gap) != nil)
    }

    @Test func fitScaleFitsWidthVerticallyAndWholePageHorizontally() {
        let vertical = PageLayoutEngine.layout(pages: pages(3), direction: .vertical)
        #expect(PageLayoutEngine.fitScale(viewport: CGSize(width: 1_280, height: 900), layout: vertical, focus: nil) == 2)
        let horizontal = PageLayoutEngine.layout(pages: pages(3), direction: .horizontal)
        let fit = PageLayoutEngine.fitScale(viewport: CGSize(width: 1_280, height: 840), layout: horizontal, focus: horizontal.entries[0].id)
        #expect(fit == 1)   // height-bound: 840 / (800 + 40)
        #expect(PageLayoutEngine.fitScale(viewport: .zero, layout: vertical, focus: nil) == 1)
    }

    @Test func snapTargetPicksNearestPageCenter() {
        let layout = PageLayoutEngine.layout(pages: pages(4), direction: .horizontal)
        let wanted = layout.entries[2]
        #expect(PageLayoutEngine.snapTarget(in: layout, projectedCenterX: wanted.frame.midX + 30) == wanted.id)
    }

    @Test func aFlickMovesExactlyOnePageInItsDirection() {
        let layout = PageLayoutEngine.layout(pages: pages(4), direction: .horizontal)
        let first = layout.entries[0], second = layout.entries[1]
        // A short flick on a phone: the scroll would coast to a point still nearest page 1.
        let short = first.frame.midX + 40
        #expect(PageLayoutEngine.snapTarget(in: layout, projectedCenterX: short, from: first.id, velocity: 0.8) == second.id)
        #expect(PageLayoutEngine.snapTarget(in: layout, projectedCenterX: short, from: second.id, velocity: -0.8) == first.id)
        // A hard flick never skips pages, and the ends stay put.
        let far = layout.entries[3].frame.midX
        #expect(PageLayoutEngine.snapTarget(in: layout, projectedCenterX: far, from: first.id, velocity: 3) == second.id)
        #expect(PageLayoutEngine.snapTarget(in: layout, projectedCenterX: short, from: first.id, velocity: -0.8) == first.id)
        // A slow release settles on the nearest page, as before.
        #expect(PageLayoutEngine.snapTarget(in: layout, projectedCenterX: short, from: first.id, velocity: 0.05) == first.id)
    }

    @Test func selectionMenuKeepsItsScreenSizeAndStaysOnThePage() {
        let sticker = CGRect(x: 237, y: 361, width: 120, height: 120)   // centered on a 595-wide page
        let corners = SelectionGeometry.corners(of: sticker, under: .identity)
        // iPhone: the page is zoomed out, so 7 actions (306 pt on screen) cover far more page than the selection.
        let phone = SelectionOverlayContent.menuFrame(corners: corners, actionCount: 7, zoom: 0.62, pageWidth: 595)
        #expect(abs(phone.width * 0.62 - 306) < 0.01)
        #expect(phone.minX >= 0 && phone.maxX <= 595)
        #expect(phone.maxX > sticker.maxX + 48, "the menu reaches beyond the old touch region around the selection")
        // Near the top edge the menu drops inside the page instead of going off it.
        let top = SelectionGeometry.corners(of: CGRect(x: 0, y: 0, width: 40, height: 40), under: .identity)
        let clamped = SelectionOverlayContent.menuFrame(corners: top, actionCount: 3, zoom: 1, pageWidth: 595)
        #expect(clamped.minX >= 0 && clamped.minY >= 0)
    }

    // MARK: Selection geometry

    @Test func scaleFollowsTheDraggedCorner() {
        let anchor = CGPoint(x: 100, y: 100)
        let t = SelectionGeometry.scale(about: anchor, from: CGPoint(x: 200, y: 100), to: CGPoint(x: 300, y: 100))
        let moved = CGPoint(x: 200, y: 100).applying(t)
        #expect(abs(moved.x - 300) < 1e-9 && abs(moved.y - 100) < 1e-9)
        #expect(CGPoint(x: 100, y: 100).applying(t) == anchor)
    }

    @Test func scaleIsClamped() {
        let t = SelectionGeometry.scale(about: .zero, from: CGPoint(x: 10, y: 0), to: CGPoint(x: 100_000, y: 0))
        #expect(t.a == 20)
        let small = SelectionGeometry.scale(about: .zero, from: CGPoint(x: 10, y: 0), to: CGPoint(x: 0.0001, y: 0))
        #expect(small.a == 0.1)
    }

    @Test func rotationTurnsAboutTheCenter() {
        let center = CGPoint(x: 50, y: 50)
        let t = SelectionGeometry.rotation(about: center, from: CGPoint(x: 100, y: 50), to: CGPoint(x: 50, y: 100))
        let p = CGPoint(x: 100, y: 50).applying(t)
        #expect(abs(p.x - 50) < 1e-9 && abs(p.y - 100) < 1e-9)
    }

    @Test func boundsUnderTranslation() {
        let rect = CGRect(x: 10, y: 20, width: 30, height: 40)
        #expect(SelectionGeometry.bounds(of: rect, under: SelectionGeometry.translation(dx: 5, dy: -5)) == CGRect(x: 15, y: 15, width: 30, height: 40))
    }
}
