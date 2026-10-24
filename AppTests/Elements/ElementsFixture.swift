import CoreGraphics
import SwiftUI
import Testing
import UIKit
import SheafnoteCore
@testable import Sheafnote

/// An editor fixture with the elements feature registered.
@MainActor
struct ElementsFixture {
    let base: EditorFixture

    init(pages: Int = 1) throws {
        base = try EditorFixture(pages: pages)
        ElementsFeature.register(into: base.host)
    }

    var host: FeatureHost { base.host }
    var session: NotebookSession { base.session }
    var services: AppServices { base.services }
    var inserter: ElementInserter { ElementInserter(editor: session, host: host) }

    func page(_ index: Int = 0) throws -> PageSession { try base.page(index) }

    /// A PNG of a solid color with a transparent margin, for import tests.
    static func pngData(width: Int = 200, height: Int = 100, color: UIColor = .systemRed, transparent: Bool = true) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = !transparent
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format)
        return renderer.pngData { ctx in
            color.setFill()
            ctx.fill(CGRect(x: transparent ? 10 : 0, y: transparent ? 10 : 0,
                            width: width - (transparent ? 20 : 0), height: height - (transparent ? 20 : 0)))
        }
    }

    /// Draws one element through its renderer into a bitmap the size of the page and returns RGBA pixels.
    func pixels(of element: ElementValue, options: RenderOptions = .screen, size: CGSize = CGSize(width: 600, height: 800)) async throws -> Bitmap {
        let renderer = try #require(host.elementRenderers.renderer(for: element.kind))
        let w = Int(size.width), h = Int(size.height)
        let ctx = try #require(CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                         space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: 1, y: -1)
        try await renderer.draw(element, into: ctx, assets: services.pages, options: options)
        return Bitmap(width: w, height: h, data: Array(UnsafeBufferPointer(start: ctx.data!.assumingMemoryBound(to: UInt8.self), count: w * h * 4)))
    }

    struct Bitmap {
        let width: Int, height: Int
        let data: [UInt8]
        /// Pixel at page coordinates (y down).
        func alpha(x: Int, y: Int) -> UInt8 { data[(y * width + x) * 4 + 3] }
        func rgba(x: Int, y: Int) -> (UInt8, UInt8, UInt8, UInt8) {
            let i = (y * width + x) * 4
            return (data[i], data[i + 1], data[i + 2], data[i + 3])
        }
        var inkedPixels: Int { stride(from: 3, to: data.count, by: 4).filter { data[$0] > 0 }.count }
    }
}
