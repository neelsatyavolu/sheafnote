import CoreGraphics
import Foundation
import Testing
@testable import SheafnoteCore

@Suite("Image crop math")
struct ImageCropMathTests {
    @Test func clampKeepsRectInsideUnitSquare() {
        let c = ImageCropMath.clamped(CGRect(x: -0.2, y: 0.9, width: 0.5, height: 0.5))
        #expect(c.minX == 0 && c.maxY <= 1.000001 && c.width == 0.5 && c.height == 0.5)
    }

    @Test func clampEnforcesMinimumSize() {
        let c = ImageCropMath.clamped(CGRect(x: 0.5, y: 0.5, width: 0.001, height: 0))
        #expect(c.width == ImageCropMath.minimumCrop && c.height == ImageCropMath.minimumCrop)
    }

    @Test func clampOfOversizedCropIsFullImage() {
        #expect(ImageCropMath.clamped(CGRect(x: 0, y: 0, width: 3, height: 3)) == CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    @Test func pixelRectScalesToOriginal() {
        let r = ImageCropMath.pixelRect(for: CGRect(x: 0.25, y: 0.5, width: 0.5, height: 0.25), originalSize: CGSize(width: 400, height: 200))
        #expect(r == CGRect(x: 100, y: 100, width: 200, height: 50))
    }

    @Test func croppingKeepsPictureScaleAndPosition() {
        let full = CGRect(x: 0, y: 0, width: 1, height: 1)
        let frame = CGRect(x: 100, y: 100, width: 200, height: 100)
        let cropped = CGRect(x: 0.5, y: 0, width: 0.5, height: 1)
        let out = ImageCropMath.frame(after: cropped, from: full, frame: frame, rotation: 0)
        #expect(out == CGRect(x: 200, y: 100, width: 100, height: 100))
    }

    @Test func uncroppingRestoresOriginalFrame() {
        let full = CGRect(x: 0, y: 0, width: 1, height: 1)
        let cropped = CGRect(x: 0.2, y: 0.1, width: 0.5, height: 0.6)
        let frame = CGRect(x: 40, y: 60, width: 300, height: 200)
        let small = ImageCropMath.frame(after: cropped, from: full, frame: frame, rotation: 0)
        let back = ImageCropMath.frame(after: full, from: cropped, frame: small, rotation: 0)
        #expect(abs(back.minX - frame.minX) < 0.001 && abs(back.width - frame.width) < 0.001)
        #expect(abs(back.minY - frame.minY) < 0.001 && abs(back.height - frame.height) < 0.001)
    }

    @Test func rotatedCropShiftsCentreAlongRotatedAxes() {
        let full = CGRect(x: 0, y: 0, width: 1, height: 1)
        let frame = CGRect(x: 0, y: 0, width: 100, height: 100)
        let right = CGRect(x: 0.5, y: 0, width: 0.5, height: 1)
        let out = ImageCropMath.frame(after: right, from: full, frame: frame, rotation: .pi / 2)
        // Local +x points down the page after a quarter turn, so the centre moves down by 25.
        #expect(abs(out.midX - 50) < 0.001)
        #expect(abs(out.midY - 75) < 0.001)
        #expect(out.size == CGSize(width: 50, height: 100))
    }

    @Test func insertionFitsPageAndKeepsAspect() {
        let f = ImageCropMath.insertionFrame(imageSize: CGSize(width: 4000, height: 2000), pageSize: CGSize(width: 600, height: 800),
                                             center: CGPoint(x: 300, y: 400))
        #expect(abs(f.width - 360) < 0.001 && abs(f.height - 180) < 0.001)
        #expect(abs(f.midX - 300) < 0.001)
    }

    @Test func smallImagesAreNotUpscaled() {
        let f = ImageCropMath.insertionFrame(imageSize: CGSize(width: 100, height: 50), pageSize: CGSize(width: 600, height: 800),
                                             center: CGPoint(x: 300, y: 400))
        #expect(f.size == CGSize(width: 100, height: 50))
    }

    @Test func insertionStaysOnPage() {
        let f = ImageCropMath.insertionFrame(imageSize: CGSize(width: 300, height: 300), pageSize: CGSize(width: 600, height: 800),
                                             center: CGPoint(x: 590, y: 10))
        #expect(f.maxX <= 600 && f.minY >= 0)
    }

    @Test func zeroSizedImageDoesNotCrash() {
        let f = ImageCropMath.insertionFrame(imageSize: .zero, pageSize: CGSize(width: 600, height: 800), center: .zero)
        #expect(f.size == .zero)
    }

    @Test func imagePayloadRoundTrips() throws {
        let p = ImagePayload(cropRect: CGRect(x: 0.1, y: 0.2, width: 0.5, height: 0.4), originalSize: CGSize(width: 800, height: 600))
        #expect(PayloadCodec.decode(ImagePayload.self, from: PayloadCodec.encode(p)) == p)
    }
}

@Suite("Text box layout and payload")
struct TextBoxLayoutTests {
    @Test func newFrameStartsAtTap() {
        let f = TextBoxLayout.newFrame(at: CGPoint(x: 50, y: 70), pageSize: CGSize(width: 600, height: 800))
        #expect(f.origin == CGPoint(x: 50, y: 70) && f.size == TextBoxLayout.defaultSize)
    }

    @Test func newFrameIsShiftedOntoPage() {
        let f = TextBoxLayout.newFrame(at: CGPoint(x: 590, y: 790), pageSize: CGSize(width: 600, height: 800))
        #expect(f.maxX <= 600 && f.maxY <= 800 && f.minX >= 0)
    }

    @Test func newFrameNarrowerThanPageIsShrunk() {
        let f = TextBoxLayout.newFrame(at: .zero, pageSize: CGSize(width: 100, height: 300))
        #expect(f.width == 100)
    }

    @Test func boxesGrowButNeverShrink() {
        #expect(TextBoxLayout.fittedHeight(contentHeight: 200, current: 48) == 212)
        #expect(TextBoxLayout.fittedHeight(contentHeight: 10, current: 120) == 120)
        #expect(TextBoxLayout.fittedHeight(contentHeight: 0, current: 0) == TextBoxLayout.minimumSize.height)
    }

    @Test func nextZIndexIsOnTop() {
        let page = UUID()
        let items = [ElementValue(pageID: page, kind: .text, frame: .zero, zIndex: 3), ElementValue(pageID: page, kind: .image, frame: .zero, zIndex: 7)]
        #expect(TextBoxLayout.nextZIndex(in: items) == 8)
        #expect(TextBoxLayout.nextZIndex(in: []) == 0)
    }

    @Test func textPayloadRoundTripsAllStyling() throws {
        let p = TextPayload(text: "Héllo\nworld", fontName: "Georgia", fontSize: 22, colorHex: "#112233", isBold: true,
                            isItalic: true, isUnderlined: true, alignment: .center, backgroundHex: "#FFEEAA", link: .url(URL(string: "https://example.com")!))
        let data = PayloadCodec.encode(p)
        #expect(PayloadCodec.decode(TextPayload.self, from: data) == p)
    }

    @Test func textPayloadDefaults() {
        let p = TextPayload(text: "")
        #expect(p.fontSize == 18 && !p.isBold && p.alignment == .leading && p.backgroundHex == nil)
    }

    @Test func garbageTextPayloadDecodesToNil() {
        #expect(PayloadCodec.decode(TextPayload.self, from: Data("{".utf8)) == nil)
    }
}
