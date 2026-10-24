import CoreGraphics
import Foundation
import SwiftData

public extension SortKey {
    /// `count` ascending keys strictly between `a` and `b`, split by bisection so key length grows with log(count),
    /// not with count (a 500-page insert stays short).
    static func spread(_ count: Int, between a: String?, and b: String?) -> [String] {
        guard count > 0 else { return [] }
        let half = (count - 1) / 2
        let middle = between(a, b)
        return spread(half, between: a, and: middle) + [middle] + spread(count - 1 - half, between: middle, and: b)
    }
}

/// One page to create: its size and what is drawn behind the ink.
struct PagePlan {
    var size: CGSize
    var backgroundAssetID: UUID
    var backgroundPageIndex: Int?
}

/// Adds planned pages to a notebook inside the caller's transaction (no save here).
@MainActor
struct PageInserter {
    let context: ModelContext
    let pages: PageStore
    let now: Date

    /// Creates the pages at `position`. `reuse` is a page that already exists and is still blank; it becomes the first
    /// planned page (used for a freshly created notebook, which starts with one empty page).
    func insert(_ plans: [PagePlan], into notebookID: UUID, at position: PagePosition, reuse: Page? = nil) throws -> [Page] {
        let siblings = try pages.orderedPages(of: notebookID).filter { $0.id != reuse?.id }
        let (lower, upper) = Self.bounds(for: position, in: siblings)
        let keys = SortKey.spread(plans.count, between: lower, and: upper)
        var created: [Page] = []
        for (index, plan) in plans.enumerated() {
            let page: Page
            if index == 0, let reuse {
                page = reuse
                page.sortKey = keys[index]
                page.widthPts = Double(plan.size.width)
                page.heightPts = Double(plan.size.height)
            } else {
                page = Page(notebookID: notebookID, sortKey: keys[index], size: plan.size, now: now)
                context.insert(page)
            }
            page.backgroundAssetID = plan.backgroundAssetID
            page.backgroundPageIndex = plan.backgroundPageIndex
            page.template = .blank
            markDirty(page, fields: LibraryStore.pageFields, now: now)
            created.append(page)
        }
        return created
    }

    private static func bounds(for position: PagePosition, in siblings: [Page]) -> (String?, String?) {
        switch position {
        case .end:
            return (siblings.last?.sortKey, nil)
        case .before(let id):
            guard let i = siblings.firstIndex(where: { $0.id == id }) else { return (siblings.last?.sortKey, nil) }
            return (i > 0 ? siblings[i - 1].sortKey : nil, siblings[i].sortKey)
        case .after(let id):
            guard let i = siblings.firstIndex(where: { $0.id == id }) else { return (siblings.last?.sortKey, nil) }
            return (siblings[i].sortKey, i + 1 < siblings.count ? siblings[i + 1].sortKey : nil)
        }
    }
}
