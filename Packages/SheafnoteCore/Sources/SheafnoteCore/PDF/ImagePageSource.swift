import CoreGraphics
import Foundation
import ImageIO

/// An image used as a whole-page background (imported photos and scans). Orientation metadata is applied.
public final class ImagePageSource: @unchecked Sendable {
    private let source: CGImageSource
    private let lock = NSLock()
    private var cached: (maxPixel: Int, image: CGImage)?
    /// Displayed size in pixels (EXIF orientation applied).
    public let pixelSize: CGSize

    public init(data: Data, name: String = "image") throws {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0,
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
              let h = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue, w >= 1, h >= 1
        else { throw PdfIOError.unreadableImage(name) }
        let orientation = (props[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        self.source = source
        self.pixelSize = (5...8).contains(orientation) ? CGSize(width: h, height: w) : CGSize(width: w, height: h)
    }

    /// The image with orientation applied, downsampled so its longer side is at most `maxPixel`.
    public func cgImage(maxPixel: Int = 4096) -> CGImage? {
        lock.withLock {
            if let cached, cached.maxPixel >= maxPixel || cached.maxPixel >= Int(max(pixelSize.width, pixelSize.height)) {
                return cached.image
            }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            ]
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
            cached = (maxPixel, image)
            return image
        }
    }

    /// Draws the image to fill `rect` in a top-left-origin, y-down context.
    public func draw(in ctx: CGContext, rect: CGRect) {
        guard let image = cgImage() else { return }
        ctx.saveGState()
        ctx.translateBy(x: rect.minX, y: rect.maxY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(origin: .zero, size: rect.size))
        ctx.restoreGState()
    }

    /// Page size for an imported image: the aspect ratio of the picture, with the longer side at A4's long edge.
    public static func pageSize(forPixels pixels: CGSize) -> CGSize {
        let longSide = PaperSize.a4.portraitSize.height
        let scale = longSide / max(pixels.width, pixels.height)
        return CGSize(width: max(1, (pixels.width * scale).rounded()), height: max(1, (pixels.height * scale).rounded()))
    }
}
