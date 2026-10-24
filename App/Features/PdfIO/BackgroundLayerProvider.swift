import UIKit
import SheafnoteCore

/// The `.background` page layer: a PDF page or an image behind the ink. Live pages draw it as vectors in tiles
/// (`BackgroundTiledView`); exports and thumbnails draw straight into the export context.
@MainActor
final class BackgroundLayerProvider: PageLayerProvider {
    let slot = PageLayerSlot.background
    let order = 0
    private let cache: BackgroundAssetCache
    private unowned let services: AppServices

    init(services: AppServices, cache: BackgroundAssetCache) {
        self.services = services
        self.cache = cache
    }

    func isActive(for page: PageSnapshot) -> Bool { page.backgroundAssetID != nil }

    func makeLayerView(for page: PageContext) -> UIView {
        guard let stored = services.pages.page(id: page.pageID), let assetID = stored.backgroundAssetID else { return UIView() }
        let view = BackgroundTiledView(size: page.pageSize, pageIndex: stored.backgroundPageIndex)
        view.load(assetID: assetID, from: cache)
        return view
    }

    func draw(page: PageSnapshot, into ctx: CGContext, rect: CGRect, options: RenderOptions) async throws {
        guard let assetID = page.backgroundAssetID else { return }
        let asset = try await cache.asset(assetID)
        asset.draw(pageIndex: page.backgroundPageIndex, in: ctx, rect: CGRect(origin: .zero, size: page.size))
    }
}
