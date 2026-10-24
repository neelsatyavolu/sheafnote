import CoreGraphics
import Foundation
import SheafnoteCore

/// Where every page sits in the scrollable content (points, zoom 1). Pure value type so it can be tested without UIKit.
struct PageLayout: Equatable {
    struct Entry: Equatable {
        let id: UUID
        let frame: CGRect
    }

    var entries: [Entry]
    var contentSize: CGSize
    var direction: ScrollDirection

    static let empty = PageLayout(entries: [], contentSize: .zero, direction: .vertical)

    func frame(of id: UUID) -> CGRect? { entries.first { $0.id == id }?.frame }

    func index(of id: UUID) -> Int? { entries.firstIndex { $0.id == id } }

    /// Pages whose frame intersects `rect`. Binary search along the scroll axis, so 1 000 pages cost the same as 10.
    func pages(intersecting rect: CGRect) -> [UUID] {
        guard !entries.isEmpty else { return [] }
        var lo = 0, hi = entries.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if maxAlongAxis(entries[mid].frame) < minAlongAxis(rect) { lo = mid + 1 } else { hi = mid }
        }
        var result: [UUID] = []
        var i = lo
        while i < entries.count, minAlongAxis(entries[i].frame) <= maxAlongAxis(rect) {
            if entries[i].frame.intersects(rect) { result.append(entries[i].id) }
            i += 1
        }
        return result
    }

    /// The page the reader is looking at: the one containing the center of the visible rect, else the nearest.
    func currentPage(visibleRect: CGRect) -> UUID? {
        guard !entries.isEmpty else { return nil }
        let center = CGPoint(x: visibleRect.midX, y: visibleRect.midY)
        if let hit = entries.first(where: { $0.frame.contains(center) }) { return hit.id }
        return entries.min { distance($0.frame, center) < distance($1.frame, center) }?.id
    }

    private func distance(_ frame: CGRect, _ p: CGPoint) -> CGFloat {
        let dx = max(frame.minX - p.x, 0, p.x - frame.maxX)
        let dy = max(frame.minY - p.y, 0, p.y - frame.maxY)
        return hypot(dx, dy)
    }

    private func minAlongAxis(_ r: CGRect) -> CGFloat { direction == .vertical ? r.minY : r.minX }
    private func maxAlongAxis(_ r: CGRect) -> CGFloat { direction == .vertical ? r.maxY : r.maxX }
}

enum PageLayoutEngine {
    static let spacing: CGFloat = 20
    static let margin: CGFloat = 20

    static func layout(pages: [(id: UUID, size: CGSize)], direction: ScrollDirection) -> PageLayout {
        guard !pages.isEmpty else { return PageLayout(entries: [], contentSize: .zero, direction: direction) }
        switch direction {
        case .vertical:
            let width = (pages.map(\.size.width).max() ?? 0) + 2 * margin
            var y = margin
            var entries: [PageLayout.Entry] = []
            for page in pages {
                entries.append(.init(id: page.id, frame: CGRect(x: (width - page.size.width) / 2, y: y,
                                                                 width: page.size.width, height: page.size.height)))
                y += page.size.height + spacing
            }
            return PageLayout(entries: entries, contentSize: CGSize(width: width, height: y - spacing + margin), direction: .vertical)
        case .horizontal:
            let height = (pages.map(\.size.height).max() ?? 0) + 2 * margin
            var x = margin
            var entries: [PageLayout.Entry] = []
            for page in pages {
                entries.append(.init(id: page.id, frame: CGRect(x: x, y: (height - page.size.height) / 2,
                                                                 width: page.size.width, height: page.size.height)))
                x += page.size.width + spacing
            }
            return PageLayout(entries: entries, contentSize: CGSize(width: x - spacing + margin, height: height), direction: .horizontal)
        }
    }

    /// Zoom that makes the pages fit the viewport: widest page across for vertical scrolling, the focused page
    /// entirely for horizontal paging.
    static func fitScale(viewport: CGSize, layout: PageLayout, focus: UUID?) -> CGFloat {
        guard viewport.width > 0, viewport.height > 0, layout.contentSize.width > 0, layout.contentSize.height > 0 else { return 1 }
        switch layout.direction {
        case .vertical:
            return viewport.width / layout.contentSize.width
        case .horizontal:
            let frame = focus.flatMap { layout.frame(of: $0) } ?? layout.entries.first?.frame ?? .zero
            guard frame.width > 0, frame.height > 0 else { return 1 }
            return min(viewport.width / (frame.width + 2 * margin), viewport.height / (frame.height + 2 * margin))
        }
    }

    /// Which page a paged horizontal scroll should settle on, given where the viewport's center would land.
    static func snapTarget(in layout: PageLayout, projectedCenterX: CGFloat) -> UUID? {
        layout.entries.min { abs($0.frame.midX - projectedCenterX) < abs($1.frame.midX - projectedCenterX) }?.id
    }

    /// Scroll velocity (points per millisecond) above which a release counts as a flick.
    static let flickVelocity: CGFloat = 0.3

    /// Like a paged scroll view: a flick moves one page from `current` in its direction (positive velocity is toward
    /// later pages); a slow release settles on the page nearest the projected center.
    static func snapTarget(in layout: PageLayout, projectedCenterX: CGFloat, from current: UUID?, velocity: CGFloat) -> UUID? {
        guard abs(velocity) > flickVelocity, let current, let index = layout.index(of: current) else {
            return snapTarget(in: layout, projectedCenterX: projectedCenterX)
        }
        let next = min(max(index + (velocity > 0 ? 1 : -1), 0), layout.entries.count - 1)
        return layout.entries[next].id
    }
}
