import CoreGraphics
import CryptoKit
import Foundation
import SheafnoteCore

/// Draws a page by asking every registered layer provider, bottom to top, into a context whose origin is the page's
/// top-left corner in page points. Implements the shared `PageRenderer` (thumbnails, export, search, flashcards).
@MainActor
final class EditorPageRenderer: PageRenderer {
    private unowned let host: FeatureHost
    private let cache = ThumbnailCache()

    init(host: FeatureHost) { self.host = host }

    private var services: AppServices { host.services }

    func renderImage(pageID: UUID, rect: CGRect?, scale: CGFloat, options: RenderOptions) async throws -> CGImage {
        let snapshot = try snapshot(for: pageID)
        let area = rect ?? CGRect(origin: .zero, size: snapshot.size)
        let width = max(1, Int((area.width * scale).rounded())), height = max(1, Int((area.height * scale).rounded()))
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw PageRenderError.renderFailed }
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: scale, y: -scale)
        ctx.translateBy(x: -area.minX, y: -area.minY)
        try await drawLayers(of: snapshot, into: ctx, rect: area, options: options)
        guard let image = ctx.makeImage() else { throw PageRenderError.renderFailed }
        return image
    }

    func renderPDFPage(pageID: UUID, into ctx: CGContext, mediaBox: CGRect, options: RenderOptions) async throws {
        let snapshot = try snapshot(for: pageID)
        guard snapshot.size.width > 0, snapshot.size.height > 0 else { throw PageRenderError.renderFailed }
        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.translateBy(x: mediaBox.minX, y: mediaBox.maxY)
        ctx.scaleBy(x: mediaBox.width / snapshot.size.width, y: -mediaBox.height / snapshot.size.height)
        try await drawLayers(of: snapshot, into: ctx, rect: CGRect(origin: .zero, size: snapshot.size), options: options)
    }

    func thumbnail(pageID: UUID, width: CGFloat) async -> CGImage? {
        guard let snapshot = try? snapshot(for: pageID), snapshot.size.width > 0 else { return nil }
        let key = signature(for: snapshot, width: width)
        if let cached = cache.image(for: key) { return cached }
        guard let image = try? await renderImage(pageID: pageID, rect: nil, scale: width / snapshot.size.width, options: .screen) else {
            return nil
        }
        cache.store(image, for: key)
        return image
    }

    // MARK: Helpers

    private func drawLayers(of snapshot: PageSnapshot, into ctx: CGContext, rect: CGRect, options: RenderOptions) async throws {
        for provider in host.layers.providers(for: snapshot) where isIncluded(provider.slot, options) {
            ctx.saveGState()
            try await provider.draw(page: snapshot, into: ctx, rect: rect, options: options)
            ctx.restoreGState()
        }
    }

    private func isIncluded(_ slot: PageLayerSlot, _ options: RenderOptions) -> Bool {
        switch slot {
        case .paper: true
        case .template, .background: options.includeBackground
        case .belowInk, .aboveInk: options.includeElements
        case .ink: options.includeInk
        case .overlay: false
        }
    }

    private func snapshot(for pageID: UUID) throws -> PageSnapshot {
        guard let page = services.pages.page(id: pageID), let notebook = services.library.notebook(id: page.notebookID) else {
            throw PageRenderError.pageMissing
        }
        return PageSnapshotFactory.make(page: page, notebook: notebook)
    }

    /// Changes whenever anything visible on the page changes, so cached thumbnails are never stale.
    private func signature(for snapshot: PageSnapshot, width: CGFloat) -> String {
        let page = services.pages.page(id: snapshot.pageID)
        let elements = (try? services.pages.elements(on: snapshot.pageID)) ?? []
        var hasher = SHA256()
        hasher.update(data: Data("\(page?.inkHash ?? "")|\(snapshot.template.kind.rawValue)|\(snapshot.paperColor.rawValue)".utf8))
        hasher.update(data: Data("|\(snapshot.backgroundAssetID?.uuidString ?? "")|\(snapshot.backgroundPageIndex ?? -1)|\(Int(width))".utf8))
        hasher.update(data: Data("|\(Int(snapshot.size.width))x\(Int(snapshot.size.height))".utf8))
        for element in elements {
            hasher.update(data: Data("|\(element.id)|\(element.frame)|\(element.rotation)|\(element.zIndex)".utf8))
            hasher.update(data: element.payload)
        }
        let digest = hasher.finalize().prefix(12).map { String(format: "%02x", $0) }.joined()
        return "\(snapshot.pageID.uuidString)-\(digest)"
    }
}
