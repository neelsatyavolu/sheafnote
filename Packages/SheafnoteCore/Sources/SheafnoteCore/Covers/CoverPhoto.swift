import CoreGraphics
import Foundation

/// Turns a picked photo or image file into the JPEG stored in `CoverSpec.image`.
public enum CoverPhoto {
    /// 3:4 like the drawn covers, small enough that the notebook record still syncs.
    public static let pixelSize = CGSize(width: 600, height: 800)
    public static let jpegQuality = 0.75

    /// Center-crops `data` (any format ImageIO reads, camera orientation applied) to fill `pixelSize`. Nil if unreadable.
    public static func jpeg(from data: Data) -> Data? {
        guard let source = try? ImagePageSource(data: data) else { return nil }
        let full = source.pixelSize
        let scale = max(pixelSize.width / full.width, pixelSize.height / full.height)
        // Decode no larger than needed: the longer side at the size it is drawn, never above the original.
        let needed = Int((max(full.width, full.height) * min(scale, 1)).rounded(.up))
        guard let image = source.cgImage(maxPixel: max(needed, 1)),
              let ctx = CGContext(data: nil, width: Int(pixelSize.width), height: Int(pixelSize.height), bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        let drawn = CGSize(width: full.width * scale, height: full.height * scale)
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(origin: .zero, size: pixelSize))
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: (pixelSize.width - drawn.width) / 2, y: (pixelSize.height - drawn.height) / 2,
                                   width: drawn.width, height: drawn.height))
        guard let cropped = ctx.makeImage() else { return nil }
        return try? ImageEncoder.encode(cropped, as: .jpeg, jpegQuality: jpegQuality)
    }
}
