import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum ExportError: LocalizedError, Equatable {
    case noPages
    case cannotCreate(String)
    case encodeFailed

    public var errorDescription: String? {
        switch self {
        case .noPages: "There are no pages to export."
        case .cannotCreate(let name): "Sheafnote couldn't create \(name)."
        case .encodeFailed: "Sheafnote couldn't encode the image."
        }
    }
}

/// Writes pages into a PDF file. The caller draws each page; this owns the PDF context and cleans up on failure.
@MainActor
public enum PDFExportWriter {
    public typealias DrawPage = @MainActor (_ index: Int, _ ctx: CGContext, _ mediaBox: CGRect) async throws -> Void

    /// Each page gets a media box of `sizes[i]` points. The draw closure receives the raw PDF context for that page
    /// (origin bottom-left, as `PageRenderer.renderPDFPage` expects). A partly written file is deleted on any error.
    public static func write(sizes: [CGSize], to url: URL, title: String?, progress: (@MainActor (Double) -> Void)? = nil,
                             draw: DrawPage) async throws {
        guard let firstSize = sizes.first else { throw ExportError.noPages }
        var firstBox = CGRect(origin: .zero, size: firstSize)
        var info: [CFString: Any] = [kCGPDFContextCreator: "Sheafnote"]
        if let title { info[kCGPDFContextTitle] = title }
        guard let ctx = CGContext(url as CFURL, mediaBox: &firstBox, info as CFDictionary) else {
            throw ExportError.cannotCreate(url.lastPathComponent)
        }
        do {
            for (index, size) in sizes.enumerated() {
                try Task.checkCancellation()
                var box = CGRect(origin: .zero, size: size)
                let pageInfo = [kCGPDFContextMediaBox as String: Data(bytes: &box, count: MemoryLayout<CGRect>.size)] as CFDictionary
                ctx.beginPDFPage(pageInfo)
                do { try await draw(index, ctx, box) } catch { ctx.endPDFPage(); throw error }
                ctx.endPDFPage()
                progress?(Double(index + 1) / Double(sizes.count))
            }
            ctx.closePDF()
        } catch {
            ctx.closePDF()
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }
}

public enum ImageEncoder {
    /// PNG keeps transparency (pages exported without their paper); JPEG is flattened onto white.
    public static func encode(_ image: CGImage, as format: ExportFormat, jpegQuality: Double = 0.9) throws -> Data {
        let source: CGImage
        let type: UTType
        switch format {
        case .png:
            source = image
            type = .png
        case .jpeg:
            source = flattenedOnWhite(image) ?? image
            type = .jpeg
        case .pdf:
            throw ExportError.encodeFailed
        }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else {
            throw ExportError.encodeFailed
        }
        let options: [CFString: Any] = format == .jpeg ? [kCGImageDestinationLossyCompressionQuality: jpegQuality] : [:]
        CGImageDestinationAddImage(destination, source, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw ExportError.encodeFailed }
        return data as Data
    }

    private static func flattenedOnWhite(_ image: CGImage) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(rect)
        ctx.draw(image, in: rect)
        return ctx.makeImage()
    }
}
