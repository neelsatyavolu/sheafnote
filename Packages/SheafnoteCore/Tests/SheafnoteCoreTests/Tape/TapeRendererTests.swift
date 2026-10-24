import CoreGraphics
import Foundation
import Testing
@testable import SheafnoteCore

@Suite("Tape renderer")
struct TapeRendererTests {
    private func centerAlpha(_ payload: TapePayload, covering: Bool) throws -> (covered: Int, center: UInt8) {
        let w = 120, h = 30
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = try #require(CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: space,
                                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        TapeRenderer.draw(payload, covering: covering, in: ctx, size: CGSize(width: w, height: h))
        let data = try #require(ctx.data)
        let px = UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: w * h * 4)
        let covered = stride(from: 3, to: px.count, by: 4).filter { px[$0] > 200 }.count
        return (covered, px[((h / 2) * w + w / 2) * 4 + 3])
    }

    @Test func coveringTapeIsOpaque() throws {
        for style in TapeStyle.allCases {
            let r = try centerAlpha(TapePayload(colorHex: "#336699", style: style), covering: true)
            #expect(r.center == 255, "style \(style)")
            #expect(r.covered > 120 * 30 / 2)
        }
    }

    @Test func revealedTapeLetsContentShowThrough() throws {
        for style in TapeStyle.allCases {
            let r = try centerAlpha(TapePayload(colorHex: "#336699", isRevealed: true, style: style), covering: false)
            #expect(r.center < 80 && r.center > 0, "style \(style)")
        }
    }

    @Test func degenerateSizeDoesNothing() throws {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = try #require(CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 16, space: space,
                                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        TapeRenderer.draw(TapePayload(colorHex: "#000000"), covering: true, in: ctx, size: .zero)
    }
}
