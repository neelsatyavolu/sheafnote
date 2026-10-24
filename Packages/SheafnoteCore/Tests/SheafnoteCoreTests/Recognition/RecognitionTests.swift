import CoreGraphics
import CoreText
import Foundation
import Testing
@testable import SheafnoteCore

@Suite struct RecognitionTests {
    static func render(_ text: String, size: CGSize = CGSize(width: 900, height: 220)) -> CGImage {
        let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(origin: .zero, size: size))
        let font = CTFontCreateWithName("Helvetica" as CFString, 96, nil)
        let attrs: [CFString: Any] = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: CGColor(gray: 0, alpha: 1)]
        let line = CTLineCreateWithAttributedString(CFAttributedStringCreate(nil, text as CFString, attrs as CFDictionary))
        ctx.textPosition = CGPoint(x: 30, y: 70)
        CTLineDraw(line, ctx)
        return ctx.makeImage()!
    }

    @Test func recognizesRenderedWords() async throws {
        let result = try await VisionHandwritingRecognizer().recognizeText(in: Self.render("Hello Sheafnote"), languages: [])
        let text = result.fullText.lowercased()
        #expect(text.contains("hello"))
        #expect(text.contains("sheaf"))
        #expect(result.lines.first?.confidence ?? 0 > 0.3)
    }

    @Test func explicitLanguageWorks() async throws {
        let result = try await VisionHandwritingRecognizer().recognizeText(in: Self.render("Notebook"), languages: ["en-US"])
        #expect(result.fullText.lowercased().contains("notebook"))
    }

    @Test func blankImageGivesNoLines() async throws {
        let blank = Self.render("")
        let result = try await VisionHandwritingRecognizer().recognizeText(in: blank, languages: [])
        #expect(result.lines.isEmpty)
        #expect(result.fullText.isEmpty)
    }

    @Test func linesAreInReadingOrder() async throws {
        let size = CGSize(width: 900, height: 400)
        let ctx = CGContext(data: nil, width: 900, height: 400, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(gray: 1, alpha: 1)); ctx.fill(CGRect(origin: .zero, size: size))
        let font = CTFontCreateWithName("Helvetica" as CFString, 90, nil)
        for (i, word) in ["First", "Second"].enumerated() {
            let attrs: [CFString: Any] = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: CGColor(gray: 0, alpha: 1)]
            let line = CTLineCreateWithAttributedString(CFAttributedStringCreate(nil, word as CFString, attrs as CFDictionary))
            ctx.textPosition = CGPoint(x: 30, y: 270 - CGFloat(i) * 170)
            CTLineDraw(line, ctx)
        }
        let result = try await VisionHandwritingRecognizer().recognizeText(in: ctx.makeImage()!, languages: [])
        #expect(result.fullText.lowercased().contains("first"))
        let t = result.fullText.lowercased()
        if let a = t.range(of: "first"), let b = t.range(of: "second") { #expect(a.lowerBound < b.lowerBound) }
    }

    @Test func errorsHaveFriendlyText() {
        #expect(RecognitionError.cancelled.errorDescription?.isEmpty == false)
        #expect(RecognitionError.visionFailed("x").errorDescription?.contains("x") == true)
    }
}
