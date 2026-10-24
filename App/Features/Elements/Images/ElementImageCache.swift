import UIKit
import SheafnoteCore

/// Decoded, screen-sized copies of stored image assets. The originals stay in the store untouched.
@MainActor
final class ElementImageCache {
    nonisolated static let screenMaxPixel = 2400
    private let cache = NSCache<NSString, UIImage>()
    private let pages: PageStore

    init(pages: PageStore) {
        self.pages = pages
        cache.totalCostLimit = 160 * 1024 * 1024
    }

    func cachedImage(for assetID: UUID) -> UIImage? { cache.object(forKey: assetID.uuidString as NSString) }

    /// The asset as a UIImage, or nil while the data is not on this device (for example before iCloud delivered it).
    func image(for assetID: UUID) async -> UIImage? {
        if let hit = cachedImage(for: assetID) { return hit }
        guard let data = try? await pages.data(for: assetID) else { return nil }
        let cgImage = await Task.detached(priority: .userInitiated) { ImageImporter.decode(data, maxPixel: Self.screenMaxPixel) }.value
        guard let cgImage else { return nil }
        let image = UIImage(cgImage: cgImage)
        cache.setObject(image, forKey: assetID.uuidString as NSString, cost: cgImage.width * cgImage.height * 4)
        return image
    }
}
