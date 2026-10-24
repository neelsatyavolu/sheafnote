import CoreGraphics
import Foundation
import QuartzCore
import UIKit
import os
import SheafnoteCore

/// Everything the tile drawing needs. Plain values so the background drawing threads can read it safely.
struct TemplateContent: Sendable {
    var spec: TemplateSpec
    var paper: PaperColor
    var size: CGSize
    var strings: TemplateStrings
}

/// Draws the page template as vectors in tiles, so it stays crisp at any zoom without a page-sized bitmap.
final class TemplateTiledLayer: CATiledLayer {
    private let content = OSAllocatedUnfairLock<TemplateContent?>(initialState: nil)

    func setContent(_ value: TemplateContent) { content.withLock { $0 = value } }

    override class func fadeDuration() -> CFTimeInterval { 0 }

    override func draw(in ctx: CGContext) {
        guard let value = content.withLock({ $0 }) else { return }
        // Layer contexts differ in orientation between configurations; the sign of `d` tells which one we got.
        if ctx.ctm.d < 0 {
            TemplateRenderer.draw(value.spec, size: value.size, paper: value.paper, in: ctx, includePaper: false, strings: value.strings)
        } else {
            TemplateRenderer.drawFlipped(value.spec, size: value.size, paper: value.paper, in: ctx, includePaper: false, strings: value.strings)
        }
    }
}

final class TemplateTiledView: UIView {
    override class var layerClass: AnyClass { TemplateTiledLayer.self }

    private var tiled: TemplateTiledLayer { layer as! TemplateTiledLayer }   // layerClass guarantees the type

    init(content: TemplateContent) {
        super.init(frame: CGRect(origin: .zero, size: content.size))
        isOpaque = false
        backgroundColor = .clear
        isUserInteractionEnabled = false
        tiled.tileSize = CGSize(width: 512, height: 512)
        tiled.levelsOfDetail = 1
        tiled.levelsOfDetailBias = 4
        tiled.setContent(content)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}
