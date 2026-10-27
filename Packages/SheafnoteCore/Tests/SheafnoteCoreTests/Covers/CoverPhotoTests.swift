import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import SheafnoteCore

@Suite struct CoverPhotoTests {
    /// Draws `fills` (rect, color) into a `size` bitmap and encodes it, optionally tagging an EXIF orientation.
    private func encoded(_ size: CGSize, _ fills: [(CGRect, CGColor)], type: UTType = .png, orientation: Int? = nil) throws -> Data {
        let ctx = try #require(CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
                                         bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        for (rect, color) in fills {
            ctx.setFillColor(color)
            ctx.fill(rect)
        }
        let image = try #require(ctx.makeImage())
        let data = NSMutableData()
        let dest = try #require(CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil))
        let props: [CFString: Any] = orientation.map { [kCGImagePropertyOrientation: $0] } ?? [:]
        CGImageDestinationAddImage(dest, image, props as CFDictionary)
        #expect(CGImageDestinationFinalize(dest))
        return data as Data
    }

    private func decode(_ data: Data) throws -> CGImage {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        return try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    /// RGB of the pixel at (x, y), measured from the top-left.
    private func rgb(_ image: CGImage, _ x: Int, _ y: Int) throws -> (Int, Int, Int) {
        var px = [UInt8](repeating: 0, count: 4)
        let ctx = try #require(CGContext(data: &px, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                         space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
        return (Int(px[0]), Int(px[1]), Int(px[2]))
    }

    private let red = CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)
    private let green = CGColor(srgbRed: 0, green: 1, blue: 0, alpha: 1)
    private let blue = CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1)

    @Test func outputIsA600By800JPEG() throws {
        let png = try encoded(CGSize(width: 1200, height: 500), [(CGRect(x: 0, y: 0, width: 1200, height: 500), green)])
        let out = try #require(CoverPhoto.jpeg(from: png))
        let source = try #require(CGImageSourceCreateWithData(out as CFData, nil))
        #expect(CGImageSourceGetType(source) as String? == UTType.jpeg.identifier)
        let image = try decode(out)
        #expect(image.width == 600 && image.height == 800)
    }

    @Test func smallImagesAreScaledUpToFill() throws {
        let png = try encoded(CGSize(width: 30, height: 20), [(CGRect(x: 0, y: 0, width: 30, height: 20), blue)])
        let image = try decode(try #require(CoverPhoto.jpeg(from: png)))
        #expect(image.width == 600 && image.height == 800)
        let (r, g, b) = try rgb(image, 5, 5)
        #expect(b > 200 && r < 60 && g < 60)
    }

    @Test func wideImagesKeepTheirMiddle() throws {
        // Red | green | blue thirds; a 3:4 crop of a 900×300 picture is the middle 225 points, all green.
        let png = try encoded(CGSize(width: 900, height: 300), [
            (CGRect(x: 0, y: 0, width: 300, height: 300), red),
            (CGRect(x: 300, y: 0, width: 300, height: 300), green),
            (CGRect(x: 600, y: 0, width: 300, height: 300), blue),
        ])
        let image = try decode(try #require(CoverPhoto.jpeg(from: png)))
        for (x, y) in [(5, 400), (300, 400), (594, 400)] {
            let (r, g, b) = try rgb(image, x, y)
            #expect(g > 200 && r < 60 && b < 60, "pixel \(x),\(y) = \(r),\(g),\(b)")
        }
    }

    @Test func cameraOrientationIsApplied() throws {
        // Stored landscape with red on top (CG origin is bottom-left), tagged "rotate 90° clockwise" (EXIF 6):
        // shown upright it is portrait with red on the right.
        let jpeg = try encoded(CGSize(width: 400, height: 300), [
            (CGRect(x: 0, y: 150, width: 400, height: 150), red),
            (CGRect(x: 0, y: 0, width: 400, height: 150), blue),
        ], type: .jpeg, orientation: 6)
        let image = try decode(try #require(CoverPhoto.jpeg(from: jpeg)))
        let left = try rgb(image, 60, 400), right = try rgb(image, 540, 400)
        #expect(left.2 > 200 && left.0 < 60)
        #expect(right.0 > 200 && right.2 < 60)
    }

    @Test func transparencyBecomesWhite() throws {
        let png = try encoded(CGSize(width: 300, height: 400), [])
        let image = try decode(try #require(CoverPhoto.jpeg(from: png)))
        let (r, g, b) = try rgb(image, 300, 400)
        #expect(r > 240 && g > 240 && b > 240)
    }

    @Test func unreadableDataIsRejected() {
        #expect(CoverPhoto.jpeg(from: Data()) == nil)
        #expect(CoverPhoto.jpeg(from: Data("not an image".utf8)) == nil)
    }
}
