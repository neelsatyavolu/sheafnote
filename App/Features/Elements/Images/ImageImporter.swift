import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ImageImportError: LocalizedError {
    case unreadable
    case encodeFailed

    var errorDescription: String? {
        switch self {
        case .unreadable: String(localized: "That file could not be read as an image.", table: "Elements")
        case .encodeFailed: String(localized: "The image could not be prepared for the page.", table: "Elements")
        }
    }
}

struct PreparedImage {
    let data: Data
    let pixelSize: CGSize
    let uti: String
    let hasAlpha: Bool
}

/// Normalizes picked images before they are stored: EXIF orientation is applied, very large images are scaled down
/// (to keep notebooks and iCloud sync light), and the result is PNG when it has transparency, JPEG otherwise.
enum ImageImporter {
    static let maxPixelDimension = 4096
    static let jpegQuality: CGFloat = 0.9

    static func prepare(_ data: Data) throws -> PreparedImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0 else { throw ImageImportError.unreadable }
        let natural = naturalDimension(of: source)
        guard natural > 0 else { throw ImageImportError.unreadable }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: min(maxPixelDimension, natural),
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { throw ImageImportError.unreadable }
        let alpha = hasAlpha(image)
        let type: UTType = alpha ? .png : .jpeg
        return PreparedImage(data: try encode(image, as: type), pixelSize: CGSize(width: image.width, height: image.height),
                             uti: type.identifier, hasAlpha: alpha)
    }

    /// Full-resolution decode for export, or a screen-sized decode when `maxPixel` is given.
    static func decode(_ data: Data, maxPixel: Int? = nil) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        guard let maxPixel else { return CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) }
        let limit = min(maxPixel, max(naturalDimension(of: source), 1))   // never upscale
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: limit,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private static func naturalDimension(of source: CGImageSource) -> Int {
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int else { return 0 }
        return max(w, h)
    }

    private static func hasAlpha(_ image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: false
        default: true
        }
    }

    private static func encode(_ image: CGImage, as type: UTType) throws -> Data {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil) else {
            throw ImageImportError.encodeFailed
        }
        let props: [CFString: Any] = type == .jpeg ? [kCGImageDestinationLossyCompressionQuality: jpegQuality] : [:]
        CGImageDestinationAddImage(destination, image, props as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw ImageImportError.encodeFailed }
        return output as Data
    }
}
