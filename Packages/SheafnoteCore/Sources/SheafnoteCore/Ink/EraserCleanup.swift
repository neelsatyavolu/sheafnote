import CoreGraphics
import Foundation

/// The "Standard" eraser: a pixel erase that also removes the crumbs it leaves behind, so no stray marks remain.
/// The app measures each piece of a cut stroke; these rules decide which pieces go.
public enum EraserCleanup {
    /// Positions in `after` of strokes the erase produced: pieces of strokes it cut, which were not there before.
    public static func changedIndices(before: Set<StrokeID>, after: [StrokeID]) -> [Int] {
        after.indices.filter { !before.contains(after[$0]) }
    }

    /// A piece is a crumb when its visible ink is no bigger than a nub about 1.5 ink widths long (and at least 8 pt²).
    public static func isCrumb(visibleArea: Double, inkWidth: Double) -> Bool {
        visibleArea < max(8, 1.5 * inkWidth * inkWidth)
    }

    /// Ink coverage of `image` in square points: summed alpha divided by `scale`².
    public static func inkArea(of image: CGImage, scale: Double) -> Double {
        let w = image.width, h = image.height
        guard w > 0, h > 0, scale > 0,
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue)
        else { return 0 }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let data = ctx.data else { return 0 }
        let alpha = data.bindMemory(to: UInt8.self, capacity: w * h)
        var total = 0
        for i in 0..<(w * h) { total += Int(alpha[i]) }
        return Double(total) / 255 / (scale * scale)
    }
}
