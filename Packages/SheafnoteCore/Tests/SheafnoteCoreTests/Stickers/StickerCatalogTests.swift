import CoreGraphics
import Foundation
import Testing
@testable import SheafnoteCore

@Suite("Sticker catalog")
struct StickerCatalogTests {
    @Test func idsAreUniqueAndNonEmpty() {
        let ids = StickerCatalog.all.map(\.id)
        #expect(!ids.isEmpty)
        #expect(Set(ids).count == ids.count)
        #expect(ids.allSatisfy { !$0.isEmpty && !$0.contains(" ") })
    }

    @Test func namesAreUniqueAndNonEmpty() {
        let names = StickerCatalog.all.map(\.name)
        #expect(Set(names).count == names.count)
        #expect(names.allSatisfy { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
    }

    @Test func everyCategoryHasStickers() {
        for category in StickerCategory.allCases {
            #expect(!StickerCatalog.stickers(in: category).isEmpty, "empty category \(category)")
        }
    }

    @Test func lookupFindsEverySticker() {
        for sticker in StickerCatalog.all { #expect(StickerCatalog.sticker(id: sticker.id) == sticker) }
        #expect(StickerCatalog.sticker(id: "no-such-sticker") == nil)
    }

    @Test func pathsAreValidAndInsideTheDesignBox() {
        for sticker in StickerCatalog.all {
            #expect(!sticker.layers.isEmpty, "\(sticker.id) has no layers")
            #expect(sticker.size.width > 0 && sticker.size.height > 0)
            let box = CGRect(origin: .zero, size: sticker.size).insetBy(dx: -1, dy: -1)
            for layer in sticker.layers {
                #expect(!layer.commands.isEmpty, "\(sticker.id) has an empty layer")
                #expect(layer.fill != nil || layer.stroke != nil, "\(sticker.id) has an invisible layer")
                guard case .move = layer.commands[0] else {
                    Issue.record("\(sticker.id) layer does not start with a move")
                    continue
                }
                let bounds = layer.commands.pointBounds
                #expect(bounds.isNull == false)
                #expect(bounds.minX.isFinite && bounds.maxY.isFinite)
                // Clipped pattern layers may overshoot; the base layer they clip to bounds them.
                if !layer.clipToBase { #expect(box.contains(bounds), "\(sticker.id) leaves its box: \(bounds)") }
            }
        }
    }

    @Test func colorsParse() {
        for sticker in StickerCatalog.all {
            #expect(RGBAColor(hex: sticker.primaryHex) != nil)
            #expect(RGBAColor(hex: sticker.secondaryHex) != nil)
            for layer in sticker.layers {
                for paint in [layer.fill, layer.stroke].compactMap({ $0 }) {
                    if case .fixed(let hex) = paint { #expect(RGBAColor(hex: hex) != nil, "\(sticker.id) bad hex \(hex)") }
                }
            }
        }
    }

    @Test func clippedLayersHaveABaseLayer() {
        for sticker in StickerCatalog.all where sticker.layers.dropFirst().contains(where: \.clipToBase) {
            #expect(sticker.layers[0].fill != nil, "\(sticker.id) clips to a base that cannot clip")
            #expect(sticker.layers[0].clipToBase == false)
        }
    }

    @Test func tintDerivesDarkerSecondary() throws {
        let sticker = try #require(StickerCatalog.sticker(id: "star"))
        let plain = StickerPalette.colors(for: sticker, tintHex: nil)
        #expect(plain.primary == RGBAColor(hex: sticker.primaryHex))
        let tinted = StickerPalette.colors(for: sticker, tintHex: "#336699")
        #expect(tinted.primary == RGBAColor(hex: "#336699"))
        #expect(tinted.secondary.r < tinted.primary.r)
        #expect(tinted.secondary.b < tinted.primary.b)
    }

    @Test func badTintFallsBackToDefaults() throws {
        let sticker = try #require(StickerCatalog.all.first)
        let colors = StickerPalette.colors(for: sticker, tintHex: "not a color")
        #expect(colors.primary == RGBAColor(hex: sticker.primaryHex))
    }

    @Test func payloadForStickerRoundTrips() throws {
        let payload = StickerPayload(stickerID: "heart", tintHex: "#FF0000")
        let data = PayloadCodec.encode(payload)
        #expect(PayloadCodec.decode(StickerPayload.self, from: data) == payload)
    }
}

@Suite("Sticker renderer")
struct StickerRendererTests {
    private func bitmap(_ sticker: StickerDefinition, tint: String? = nil, side: Int = 80) throws -> [UInt8] {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = try #require(CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                         space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.translateBy(x: 0, y: CGFloat(side))
        ctx.scaleBy(x: 1, y: -1)
        StickerRenderer.draw(sticker, tintHex: tint, in: ctx, rect: CGRect(x: 0, y: 0, width: side, height: side))
        let data = try #require(ctx.data)
        return Array(UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: side * side * 4))
    }

    private func coverage(_ pixels: [UInt8]) -> Int {
        stride(from: 3, to: pixels.count, by: 4).filter { pixels[$0] > 0 }.count
    }

    @Test func everyStickerPaintsSomething() throws {
        for sticker in StickerCatalog.all {
            let pixels = try bitmap(sticker)
            #expect(coverage(pixels) > 40, "\(sticker.id) rendered (almost) nothing")
        }
    }

    @Test func tintChangesColors() throws {
        let sticker = try #require(StickerCatalog.sticker(id: "circle"))
        #expect(try bitmap(sticker) != bitmap(sticker, tint: "#00AA33"))
    }

    @Test func rendersNothingOutsideTheRect() throws {
        let sticker = try #require(StickerCatalog.sticker(id: "square"))
        let side = 80
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = try #require(CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                         space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        StickerRenderer.draw(sticker, tintHex: nil, in: ctx, rect: CGRect(x: 0, y: 0, width: 40, height: 40))
        let data = try #require(ctx.data)
        let pixels = UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: side * side * 4)
        // CoreGraphics bitmap rows start at the top of memory for a default (y-up) context: the far corner stays empty.
        let farCorner = (60 * side + 60) * 4 + 3
        let farCorner2 = (10 * side + 70) * 4 + 3
        #expect(pixels[farCorner] == 0 && pixels[farCorner2] == 0)
    }
}
