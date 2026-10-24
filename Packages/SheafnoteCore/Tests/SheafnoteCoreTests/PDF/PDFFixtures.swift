import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers
@testable import SheafnoteCore

/// Generates PDFs and images for tests, in memory.
enum PDFFixtures {
    /// A PDF whose page `i` is `sizes[i]`, with a black bar across the TOP edge of each page (PDF space: high y).
    static func pdf(sizes: [CGSize], barHeight: CGFloat = 20) -> Data {
        let data = NSMutableData()
        let consumer = CGDataConsumer(data: data as CFMutableData)!
        var first = CGRect(origin: .zero, size: sizes[0])
        let ctx = CGContext(consumer: consumer, mediaBox: &first, nil)!
        for size in sizes {
            var box = CGRect(origin: .zero, size: size)
            let info = [kCGPDFContextMediaBox as String: Data(bytes: &box, count: MemoryLayout<CGRect>.size)] as CFDictionary
            ctx.beginPDFPage(info)
            ctx.setFillColor(CGColor(gray: 0, alpha: 1))
            ctx.fill(CGRect(x: 0, y: size.height - barHeight, width: size.width, height: barHeight))
            ctx.endPDFPage()
        }
        ctx.closePDF()
        return data as Data
    }

    static func pdf(pages: Int, size: CGSize = CGSize(width: 612, height: 792)) -> Data {
        pdf(sizes: Array(repeating: size, count: pages))
    }

    /// Same as `pdf(sizes:)` but with page `index` rotated by `degrees` and an outline attached.
    static func pdfWithRotation(size: CGSize, degrees: Int) -> Data {
        let document = PDFDocument(data: pdf(sizes: [size]))!
        document.page(at: 0)!.rotation = degrees
        return document.dataRepresentation()!
    }

    /// Chapter 1 (page 1) > Section 1.1 (page 3), Chapter 2 (page 2).
    static func pdfWithOutline(pageCount: Int = 4) -> Data {
        // PDFKit only writes an outline for documents it built itself, so start from blank pages, not from parsed data.
        let document = PDFDocument()
        for _ in 0..<pageCount { document.insert(PDFPage(), at: document.pageCount) }
        let root = PDFOutline()
        func item(_ title: String, page: Int) -> PDFOutline {
            let o = PDFOutline()
            o.label = title
            o.destination = PDFDestination(page: document.page(at: page)!, at: .zero)
            return o
        }
        let chapter1 = item("Chapter 1", page: 0)
        chapter1.insertChild(item("Section 1.1", page: 2), at: 0)
        root.insertChild(chapter1, at: 0)
        root.insertChild(item("Chapter 2", page: 1), at: 1)
        document.outlineRoot = root
        return document.dataRepresentation()!
    }

    static func png(width: Int, height: Int) -> Data {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let out = NSMutableData()
        let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
        CGImageDestinationFinalize(dest)
        return out as Data
    }

    /// A bitmap context with the editor's page convention (origin top-left, y down) and white background.
    static func pageContext(_ size: CGSize, scale: CGFloat = 1) -> CGContext {
        let w = Int(size.width * scale), h = Int(size.height * scale)
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: scale, y: -scale)
        return ctx
    }

    /// Luma (0...255) of the pixel at (x, y) counted from the top-left of the rendered bitmap.
    static func luma(_ ctx: CGContext, x: Int, y: Int) -> Int {
        guard let data = ctx.data else { return -1 }
        let bytes = data.bindMemory(to: UInt8.self, capacity: ctx.bytesPerRow * ctx.height)
        let offset = y * ctx.bytesPerRow + x * 4
        return (Int(bytes[offset]) + Int(bytes[offset + 1]) + Int(bytes[offset + 2])) / 3
    }
}
