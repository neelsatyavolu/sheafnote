import CoreGraphics
import Foundation

/// Geometry and auto-advance rules of the zoom window: a magnified writing strip that looks at a small "focus box"
/// on the page. What is written in the strip is mapped back to page coordinates, and the box slides along the line
/// as the pen nears the strip's right edge. Pure value type, no UI.
public struct ZoomWindowModel: Sendable, Equatable {
    public enum AdvanceResult: Sendable, Equatable {
        case movedRight
        case wrappedToNextLine
        case endOfPage
    }

    public static let magnificationRange: ClosedRange<CGFloat> = 2...8
    public static let minimumAspect: CGFloat = 1

    public private(set) var pageSize: CGSize
    public private(set) var magnification: CGFloat
    public private(set) var stripAspect: CGFloat
    public private(set) var focusOrigin: CGPoint
    /// Page points. The box returns here when a line wraps.
    public var leftMargin: CGFloat
    /// Page points. Writing past `pageWidth - rightMargin` wraps to the next line.
    public var rightMargin: CGFloat
    /// Share of the strip width where the pen triggers an advance (0.5...0.95).
    public var triggerFraction: CGFloat { didSet { triggerFraction = min(max(triggerFraction, 0.5), 0.95) } }
    public var autoAdvance = true
    /// After an advance the last pen position sits this share of the box width from its left edge.
    public var keepFraction: CGFloat = 0.12

    public init(pageSize: CGSize, magnification: CGFloat = 4, stripAspect: CGFloat = 5,
                leftMargin: CGFloat = 36, rightMargin: CGFloat = 36) {
        self.pageSize = pageSize
        self.magnification = min(max(magnification, Self.magnificationRange.lowerBound), Self.magnificationRange.upperBound)
        self.stripAspect = max(stripAspect, Self.minimumAspect)
        self.leftMargin = leftMargin
        self.rightMargin = rightMargin
        self.triggerFraction = 0.8
        self.focusOrigin = .zero
        normalizeMargins()
        focusOrigin = clamped(CGPoint(x: leftMargin - focusSize.width * keepFraction, y: leftMargin))
    }

    // MARK: Geometry

    public var focusSize: CGSize {
        let width = pageSize.width / magnification
        return CGSize(width: width, height: width / stripAspect)
    }

    public var focusRect: CGRect { CGRect(origin: focusOrigin, size: focusSize) }

    /// Distance the box drops when a new line starts.
    public var lineStep: CGFloat { focusSize.height * 0.8 }

    /// Page points per strip point.
    public func pageScale(forStrip stripSize: CGSize) -> CGFloat {
        stripSize.width > 0 ? focusSize.width / stripSize.width : 1
    }

    public func pageLocation(forStrip point: CGPoint, stripSize: CGSize) -> CGPoint {
        let scale = pageScale(forStrip: stripSize)
        return CGPoint(x: focusOrigin.x + point.x * scale, y: focusOrigin.y + point.y * scale)
    }

    // MARK: Changing the window

    public mutating func setPageSize(_ size: CGSize) {
        pageSize = size
        normalizeMargins()
        focusOrigin = clamped(focusOrigin)
    }

    public mutating func setMagnification(_ value: CGFloat) {
        magnification = min(max(value, Self.magnificationRange.lowerBound), Self.magnificationRange.upperBound)
        focusOrigin = clamped(focusOrigin)
    }

    public mutating func setStripAspect(_ value: CGFloat) {
        stripAspect = max(value, Self.minimumAspect)
        focusOrigin = clamped(focusOrigin)
    }

    public mutating func moveFocus(to origin: CGPoint) { focusOrigin = clamped(origin) }

    public mutating func moveFocus(by delta: CGSize) {
        focusOrigin = clamped(CGPoint(x: focusOrigin.x + delta.width, y: focusOrigin.y + delta.height))
    }

    public mutating func normalizeMargins() {
        let limit = max(pageSize.width / 2, 0)
        leftMargin = min(max(leftMargin, 0), limit)
        rightMargin = min(max(rightMargin, 0), limit)
    }

    // MARK: Auto-advance

    public func shouldAdvance(afterPenAtStrip point: CGPoint, stripSize: CGSize) -> Bool {
        guard autoAdvance, stripSize.width > 0 else { return false }
        return point.x / stripSize.width >= triggerFraction
    }

    /// Slides the box right so the last pen position (page x) sits near its left edge; wraps to the next line when the
    /// pen is already at the right margin.
    @discardableResult
    public mutating func advance(keepingPageX lastX: CGFloat) -> AdvanceResult {
        if lastX >= pageSize.width - rightMargin { return newLine() }
        let target = lastX - focusSize.width * keepFraction
        focusOrigin = clamped(CGPoint(x: max(target, focusOrigin.x), y: focusOrigin.y))
        return .movedRight
    }

    /// Back to the left margin one line down; stays put when the page has no room left.
    @discardableResult
    public mutating func newLine() -> AdvanceResult {
        let nextY = focusOrigin.y + lineStep
        guard nextY + focusSize.height <= pageSize.height else { return .endOfPage }
        focusOrigin = clamped(CGPoint(x: leftMargin - focusSize.width * keepFraction, y: nextY))
        return .wrappedToNextLine
    }

    private func clamped(_ origin: CGPoint) -> CGPoint {
        let size = focusSize
        let maxX = max(pageSize.width - size.width, 0), maxY = max(pageSize.height - size.height, 0)
        return CGPoint(x: min(max(origin.x, 0), maxX), y: min(max(origin.y, 0), maxY))
    }
}
