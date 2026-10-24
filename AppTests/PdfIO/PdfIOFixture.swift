import CoreGraphics
import PDFKit
import SwiftUI
import Testing
import UIKit
import SheafnoteCore
@testable import Sheafnote

/// Services plus a feature host with the editor and pdf-io registered, so exports run through the real page renderer.
@MainActor
struct PdfIOFixture {
    let services: AppServices
    let host: FeatureHost

    init() throws {
        services = try AppServices.inMemory()
        host = FeatureHost(services: services)
        EditorFeature.register(into: host)
        PdfIOFeature.register(into: host)
    }

    var importer: PdfImporter { PdfImporter(context: services.context, pages: services.pages) }

    /// A PDF with a black bar across the top of every page (UIKit space: y grows downward).
    static func pdf(pages: Int, size: CGSize = CGSize(width: 612, height: 792)) -> Data {
        UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: size)).pdfData { ctx in
            for _ in 0..<pages {
                ctx.beginPage()
                UIColor.black.setFill()
                UIRectFill(CGRect(x: 0, y: 0, width: size.width, height: 40))
            }
        }
    }

    /// Luma 0...255 at a pixel of an image (origin top-left).
    static func luma(of image: CGImage, x: Int, y: Int) -> Int {
        guard let pixel = image.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)),
              let ctx = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = ctx.data?.bindMemory(to: UInt8.self, capacity: 4) else { return -1 }
        ctx.draw(pixel, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return (Int(data[0]) + Int(data[1]) + Int(data[2])) / 3
    }

    static func temporaryFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "pdfio-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
