import CoreGraphics
import Foundation
import SheafnoteCore

/// Whiteboards (`PageSizing.infinite`) have one page that grows to the right and downward as ink approaches its edge.
extension NotebookSession {
    private static let growthMargin: CGFloat = 800
    private static let growthStep: CGFloat = 400

    func growInfinitePageIfNeeded(_ page: PageSession) {
        guard case .infinite(let initial) = sizing, page.isEditable else { return }
        let bounds = page.drawing.bounds
        guard !bounds.isNull, !bounds.isInfinite else { return }
        let width = grown(needed: bounds.maxX + Self.growthMargin, current: page.pageSize.width, base: initial.width)
        let height = grown(needed: bounds.maxY + Self.growthMargin, current: page.pageSize.height, base: initial.height)
        guard width > page.pageSize.width || height > page.pageSize.height else { return }
        let size = CGSize(width: width, height: height)
        page.resize(to: size)
        persist(size: size, for: page.pageID)
        pageSizeChanged(page.pageID, to: size)
    }

    private func grown(needed: CGFloat, current: CGFloat, base: CGFloat) -> CGFloat {
        let target = max(needed, base)
        guard target > current else { return current }
        return (target / Self.growthStep).rounded(.up) * Self.growthStep
    }

    private func persist(size: CGSize, for pageID: UUID) {
        guard let model = services.pages.page(id: pageID) else { return }
        model.widthPts = Double(size.width)
        model.heightPts = Double(size.height)
        markDirty(model, fields: ["widthPts", "heightPts"])
        do { try services.context.save() } catch { report(error) }
    }
}
