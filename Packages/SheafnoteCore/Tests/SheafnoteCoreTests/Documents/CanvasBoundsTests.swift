import CoreGraphics
import Foundation
import Testing
@testable import SheafnoteCore

@Suite struct CanvasBoundsTests {
    let initial = CGSize(width: 2000, height: 2000)

    @Test func staysAtCurrentSizeWithoutContent() {
        let size = CanvasBounds.grownSize(current: initial, content: nil, initial: initial)
        #expect(size == initial)
    }

    @Test func neverShrinksBelowInitialOrCurrent() {
        let current = CGSize(width: 3200, height: 2400)
        let size = CanvasBounds.grownSize(current: current, content: CGRect(x: 0, y: 0, width: 10, height: 10), initial: initial)
        #expect(size == current)
    }

    @Test func growsRightWhenInkApproachesTheEdge() {
        let content = CGRect(x: 1500, y: 100, width: 400, height: 50)
        let size = CanvasBounds.grownSize(current: initial, content: content, initial: initial)
        #expect(size.width >= content.maxX + CanvasBounds.growthMargin)
        #expect(size.height == initial.height)
        #expect(size.width.truncatingRemainder(dividingBy: CanvasBounds.growthStep) == 0)
    }

    @Test func growsDownwardToo() {
        let content = CGRect(x: 10, y: 1900, width: 50, height: 300)
        let size = CanvasBounds.grownSize(current: initial, content: content, initial: initial)
        #expect(size.height >= content.maxY + CanvasBounds.growthMargin)
        #expect(size.width == initial.width)
    }

    @Test func ignoresNonFiniteContent() {
        #expect(CanvasBounds.grownSize(current: initial, content: CGRect.infinite, initial: initial) == initial)
        #expect(CanvasBounds.grownSize(current: initial, content: CGRect.null, initial: initial) == initial)
    }

    @Test func unionOfStrokesAndElements() {
        let union = CanvasBounds.contentBounds(strokes: CGRect(x: 0, y: 0, width: 10, height: 10),
                                               elements: [CGRect(x: 50, y: 50, width: 10, height: 10)])
        #expect(union == CGRect(x: 0, y: 0, width: 60, height: 60))
        #expect(CanvasBounds.contentBounds(strokes: nil, elements: []) == nil)
        #expect(CanvasBounds.contentBounds(strokes: .null, elements: [CGRect(x: 1, y: 2, width: 3, height: 4)])
                == CGRect(x: 1, y: 2, width: 3, height: 4))
    }
}
