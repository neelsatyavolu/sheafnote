import SwiftUI
import Testing
import UIKit
import SheafnoteCore
@testable import Sheafnote

@MainActor
@Suite struct ElementRendererTests {
    @Test func featureRegistersRenderersToolsAndActions() throws {
        let f = try ElementsFixture()
        for kind in [ElementKind.text, .image, .sticker, .tape] {
            #expect(f.host.elementRenderers.renderer(for: kind) != nil, "missing renderer for \(kind)")
        }
        #expect(f.host.elementRenderers.renderer(for: .text)?.slot == .belowInk)
        #expect(f.host.elementRenderers.renderer(for: .image)?.slot == .belowInk)
        #expect(f.host.elementRenderers.renderer(for: .sticker)?.slot == .belowInk)
        #expect(f.host.elementRenderers.renderer(for: .tape)?.slot == .aboveInk)
        for id in [ToolID.text, .element, .tape] { #expect(f.host.tools.tool(id) != nil, "missing tool \(id.rawValue)") }
        let actionIDs = f.host.selectionActions.actions.map(\.id)
        #expect(actionIDs.contains("elements.save") && actionIDs.contains("elements.editText") && actionIDs.contains("elements.crop"))
    }

    @Test func toolsUseTheDocumentedPlacementAndInput() throws {
        let f = try ElementsFixture()
        #expect(f.host.tools.tool(.tape)?.title != nil)
        let primary = f.host.tools.tools(for: .paged).compactMap { tool -> ToolID? in
            if case .primary = tool.placement { tool.id } else { nil }
        }
        #expect(primary.contains(.element) && primary.contains(.text))
        #expect(!primary.contains(.tape))
        #expect(f.host.tools.tool(.text)?.inputPolicy == .overlayCapturesAll)
    }

    @Test func textRendererDrawsText() async throws {
        let f = try ElementsFixture()
        let page = try f.page()
        let element = ElementValue(pageID: page.pageID, kind: .text, frame: CGRect(x: 40, y: 40, width: 300, height: 80),
                                   payload: PayloadCodec.encode(TextPayload(text: "Hello", fontSize: 32)))
        let bitmap = try await f.pixels(of: element)
        #expect(bitmap.inkedPixels > 300)
        #expect(bitmap.alpha(x: 5, y: 5) == 0)
        #expect(bitmap.alpha(x: 580, y: 780) == 0)
    }

    @Test func textBackgroundFillsTheBox() async throws {
        let f = try ElementsFixture()
        let element = ElementValue(pageID: UUID(), kind: .text, frame: CGRect(x: 40, y: 40, width: 200, height: 60),
                                   payload: PayloadCodec.encode(TextPayload(text: "", backgroundHex: "#FFEE00")))
        let bitmap = try await f.pixels(of: element)
        let pixel = bitmap.rgba(x: 140, y: 70)
        #expect(pixel.0 > 240 && pixel.1 > 220 && pixel.2 < 30 && pixel.3 == 255)
    }

    @Test func rotatedTextMovesInk() async throws {
        let f = try ElementsFixture()
        let payload = PayloadCodec.encode(TextPayload(text: "Rotate me please", fontSize: 28, backgroundHex: "#000000"))
        let flat = ElementValue(pageID: UUID(), kind: .text, frame: CGRect(x: 100, y: 300, width: 300, height: 50), payload: payload)
        var turned = flat
        turned.rotation = .pi / 2
        let a = try await f.pixels(of: flat), b = try await f.pixels(of: turned)
        #expect(a.alpha(x: 390, y: 325) > 0)         // right end of the flat box
        #expect(b.alpha(x: 390, y: 325) == 0)        // after a quarter turn that spot is empty
        #expect(b.alpha(x: 250, y: 440) > 0)         // box now extends downward from its centre
    }

    @Test func stickerRendererDrawsVectorArtInsideItsFrame() async throws {
        let f = try ElementsFixture()
        let element = ElementValue(pageID: UUID(), kind: .sticker, frame: CGRect(x: 100, y: 100, width: 200, height: 200),
                                   payload: PayloadCodec.encode(StickerPayload(stickerID: "circle")))
        let bitmap = try await f.pixels(of: element)
        #expect(bitmap.alpha(x: 200, y: 200) == 255)
        #expect(bitmap.alpha(x: 90, y: 90) == 0)
        #expect(bitmap.alpha(x: 105, y: 105) == 0)     // circle corner is empty
    }

    @Test func stickerTintIsApplied() async throws {
        let f = try ElementsFixture()
        let frame = CGRect(x: 100, y: 100, width: 200, height: 200)
        let plain = ElementValue(pageID: UUID(), kind: .sticker, frame: frame, payload: PayloadCodec.encode(StickerPayload(stickerID: "circle")))
        let tinted = ElementValue(pageID: UUID(), kind: .sticker, frame: frame,
                                  payload: PayloadCodec.encode(StickerPayload(stickerID: "circle", tintHex: "#0000FF")))
        let a = try await f.pixels(of: plain).rgba(x: 200, y: 200), b = try await f.pixels(of: tinted).rgba(x: 200, y: 200)
        #expect(a != b)
        #expect(b.2 > 240 && b.0 < 10)
    }

    @Test func unknownStickerDrawsNothingAndKeepsItsData() async throws {
        let f = try ElementsFixture()
        let element = ElementValue(pageID: UUID(), kind: .sticker, frame: CGRect(x: 0, y: 0, width: 100, height: 100),
                                   payload: PayloadCodec.encode(StickerPayload(stickerID: "from-the-future")))
        #expect(try await f.pixels(of: element).inkedPixels == 0)
    }

    @Test func stickerArtViewIsUprightWhenRenderedBySwiftUI() throws {
        let sticker = try #require(StickerCatalog.sticker(id: "ribbon"))     // flat top, notch cut into the bottom centre
        let view = StickerArtView(sticker: sticker, tintHex: nil).frame(width: 100, height: 200)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        let image = try #require(renderer.cgImage)
        let data = try #require(image.dataProvider?.data)
        let bytes = CFDataGetBytePtr(data)!
        func alpha(_ x: Int, _ y: Int) -> UInt8 { bytes[y * image.bytesPerRow + x * (image.bitsPerPixel / 8) + 3] }
        #expect(alpha(50, 20) == 255)         // body near the top
        #expect(alpha(50, 190) == 0)          // the notch at the bottom centre is empty
        #expect(alpha(18, 188) > 0)           // ... but the tails on either side are filled
    }

    @Test func tapeRendererHonorsStateAndHideTape() async throws {
        let f = try ElementsFixture()
        let frame = CGRect(x: 50, y: 50, width: 200, height: 40)
        func tape(revealed: Bool) -> ElementValue {
            ElementValue(pageID: UUID(), kind: .tape, frame: frame, payload: PayloadCodec.encode(TapePayload(colorHex: "#336699", isRevealed: revealed)))
        }
        let covering = try await f.pixels(of: tape(revealed: false)).alpha(x: 150, y: 70)
        let revealed = try await f.pixels(of: tape(revealed: true)).alpha(x: 150, y: 70)
        var hide = RenderOptions.screen
        hide.hideTape = true
        let forced = try await f.pixels(of: tape(revealed: true), options: hide).alpha(x: 150, y: 70)
        #expect(covering == 255)
        #expect(revealed < 80)
        #expect(forced == 255)
    }

    @Test func imageRendererDrawsAndCrops() async throws {
        let f = try ElementsFixture()
        let data = ElementsFixture.pngData(width: 200, height: 100, color: .systemRed, transparent: false)
        let element = try f.inserter.insertImage(data: data, filename: "red.png")
        let bitmap = try await f.pixels(of: element)
        let mid = bitmap.rgba(x: Int(element.frame.midX), y: Int(element.frame.midY))
        #expect(mid.0 > 200 && mid.3 == 255)
        #expect(bitmap.alpha(x: Int(element.frame.minX) - 5, y: Int(element.frame.midY)) == 0)
        // Crop to the left half: the frame width follows and the picture is not stretched.
        var payload = try #require(element.decoded(ImagePayload.self))
        payload.cropRect = CGRect(x: 0, y: 0, width: 0.5, height: 1)
        var cropped = element
        cropped.payload = PayloadCodec.encode(payload)
        cropped.frame = ImageCropMath.frame(after: payload.cropRect, from: CGRect(x: 0, y: 0, width: 1, height: 1), frame: element.frame, rotation: 0)
        let after = try await f.pixels(of: cropped)
        #expect(after.alpha(x: Int(element.frame.maxX) - 5, y: Int(element.frame.midY)) == 0)
        #expect(after.alpha(x: Int(element.frame.minX) + 5, y: Int(element.frame.midY)) == 255)
    }

    @Test func missingImageAssetFailsLoudlyWithoutCrashing() async throws {
        let f = try ElementsFixture()
        let element = ElementValue(pageID: UUID(), kind: .image, frame: CGRect(x: 0, y: 0, width: 50, height: 50),
                                   payload: PayloadCodec.encode(ImagePayload(originalSize: CGSize(width: 10, height: 10))), assetID: UUID())
        await #expect(throws: (any Error).self) { _ = try await f.pixels(of: element) }
    }

    @Test func hitTestersFollowRotation() throws {
        let f = try ElementsFixture()
        for kind in [ElementKind.text, .image, .sticker, .tape] {
            let renderer = try #require(f.host.elementRenderers.renderer(for: kind))
            let element = ElementValue(pageID: UUID(), kind: kind, frame: CGRect(x: 100, y: 100, width: 200, height: 20), rotation: .pi / 2)
            let tester = renderer.hitTester(for: element)
            #expect(tester.contains(point: CGPoint(x: 200, y: 200)))      // along the rotated long axis
            #expect(!tester.contains(point: CGPoint(x: 290, y: 110)))     // where the unrotated box would be
            #expect(tester.bounds.height > tester.bounds.width)
        }
    }
}
