import OSLog
import QuartzCore
import UIKit
import os
import SheafnoteCore

struct BackgroundTileContent: Sendable {
    var asset: BackgroundAsset
    var pageIndex: Int?
    var size: CGSize
}

/// Draws a background in 512 pt tiles, as vectors, so it stays sharp at any zoom without a page-sized bitmap.
final class BackgroundTiledLayer: CATiledLayer {
    private let content = OSAllocatedUnfairLock<BackgroundTileContent?>(initialState: nil)

    func setContent(_ value: BackgroundTileContent?) { content.withLock { $0 = value } }

    override class func fadeDuration() -> CFTimeInterval { 0 }

    override func draw(in ctx: CGContext) {
        guard let value = content.withLock({ $0 }) else { return }
        ctx.saveGState()
        defer { ctx.restoreGState() }
        // Same convention as the template layer: tile contexts differ in orientation between configurations,
        // and the sign of `d` tells which one this is. The drawing code wants a top-left origin.
        if ctx.ctm.d >= 0 {
            ctx.translateBy(x: 0, y: value.size.height)
            ctx.scaleBy(x: 1, y: -1)
        }
        value.asset.draw(pageIndex: value.pageIndex, in: ctx, rect: CGRect(origin: .zero, size: value.size))
    }
}

final class BackgroundTiledView: UIView {
    override class var layerClass: AnyClass { BackgroundTiledLayer.self }

    private static let log = Logger(subsystem: "co.xanom.sheafnote", category: "pdf-background")
    private var tiled: BackgroundTiledLayer { layer as! BackgroundTiledLayer }   // layerClass guarantees the type
    private let pageIndex: Int?
    private let pageSize: CGSize
    private var loadTask: Task<Void, Never>?

    init(size: CGSize, pageIndex: Int?) {
        self.pageIndex = pageIndex
        self.pageSize = size
        super.init(frame: CGRect(origin: .zero, size: size))
        isOpaque = false
        backgroundColor = .clear
        isUserInteractionEnabled = false
        tiled.tileSize = CGSize(width: 512, height: 512)
        tiled.levelsOfDetail = 1
        tiled.levelsOfDetailBias = 4
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    deinit { loadTask?.cancel() }

    @MainActor
    func load(assetID: UUID, from cache: BackgroundAssetCache) {
        loadTask = Task { @MainActor [weak self] in
            do {
                let asset = try await cache.asset(assetID)
                guard let self, !Task.isCancelled else { return }
                tiled.setContent(BackgroundTileContent(asset: asset, pageIndex: pageIndex, size: pageSize))
                tiled.setNeedsDisplay()
            } catch {
                Self.log.error("Background \(assetID.uuidString, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                self?.showFailure(error)
            }
        }
    }

    @MainActor
    private func showFailure(_ error: Error) {
        let label = UILabel()
        label.text = String(localized: "The page background couldn't be loaded. Your ink is safe.", table: "PdfIO")
        label.numberOfLines = 0
        label.textAlignment = .center
        label.textColor = .secondaryLabel
        label.font = .preferredFont(forTextStyle: .footnote)
        label.adjustsFontForContentSizeCategory = true
        label.frame = bounds.insetBy(dx: 24, dy: 24)
        label.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        label.accessibilityIdentifier = "pdfio.background.failed"
        addSubview(label)
    }
}
