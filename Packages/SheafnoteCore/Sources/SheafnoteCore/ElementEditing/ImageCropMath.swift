import CoreGraphics
import Foundation

/// Geometry for cropping and placing images. Crop rectangles are in unit coordinates of the original (origin top-left).
public enum ImageCropMath {
    public static let minimumCrop: CGFloat = 0.05

    /// Forces a crop rectangle inside the unit square and at least `minimumCrop` in each direction.
    public static func clamped(_ crop: CGRect) -> CGRect {
        let w = min(max(crop.width, minimumCrop), 1)
        let h = min(max(crop.height, minimumCrop), 1)
        let x = min(max(crop.minX, 0), 1 - w)
        let y = min(max(crop.minY, 0), 1 - h)
        return CGRect(x: x, y: y, width: w, height: h)
    }

    /// The crop rectangle in pixels of the original image.
    public static func pixelRect(for crop: CGRect, originalSize: CGSize) -> CGRect {
        let c = clamped(crop)
        return CGRect(x: c.minX * originalSize.width, y: c.minY * originalSize.height,
                      width: c.width * originalSize.width, height: c.height * originalSize.height)
    }

    /// The new element frame after the crop changes from `old` to `new`, keeping the picture's on-page scale and the
    /// kept pixels where they were (so cropping tighter does not make the image jump or stretch). Rotation about
    /// the frame centre is respected.
    public static func frame(after new: CGRect, from old: CGRect, frame: CGRect, rotation: Double) -> CGRect {
        let o = clamped(old), n = clamped(new)
        let scaleX = frame.width / o.width   // page points per unit of original width
        let scaleY = frame.height / o.height
        let size = CGSize(width: n.width * scaleX, height: n.height * scaleY)
        // Offset (unrotated) between the old and new crop centres.
        let dx = (n.midX - o.midX) * scaleX
        let dy = (n.midY - o.midY) * scaleY
        let cosA = cos(rotation), sinA = sin(rotation)
        let center = CGPoint(x: frame.midX + dx * cosA - dy * sinA, y: frame.midY + dx * sinA + dy * cosA)
        return CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
    }

    /// Frame for a freshly inserted image: aspect preserved, at most `maxFraction` of the page in each direction
    /// (never upscaled past its natural point size), centred on `center`, and kept inside the page.
    public static func insertionFrame(imageSize: CGSize, pageSize: CGSize, center: CGPoint, maxFraction: CGFloat = 0.6) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return CGRect(origin: center, size: .zero) }
        let limit = CGSize(width: pageSize.width * maxFraction, height: pageSize.height * maxFraction)
        let scale = min(limit.width / imageSize.width, limit.height / imageSize.height, 1)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        var origin = CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2)
        origin.x = min(max(origin.x, 0), max(pageSize.width - size.width, 0))
        origin.y = min(max(origin.y, 0), max(pageSize.height - size.height, 0))
        return CGRect(origin: origin, size: size)
    }
}
