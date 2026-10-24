import CoreGraphics
import Foundation
import PDFKit
import UIKit
import SheafnoteCore
@testable import Sheafnote

/// Counts calls and returns canned text, so OCR tests never run Vision.
final class FakeRecognizer: HandwritingRecognizing, @unchecked Sendable {
    private let lock = NSLock()
    private var _calls = 0
    var text = "recognized words"
    var failure: (any Error)?

    var calls: Int { lock.withLock { _calls } }

    func recognizeText(in image: CGImage, languages: [String]) async throws -> RecognizedText {
        lock.withLock { _calls += 1 }
        if let failure { throw failure }
        return RecognizedText(lines: [RecognizedLine(text: text, confidence: 1, boundingBox: CGRect(x: 0, y: 0.5, width: 1, height: 0.1))])
    }
}

/// A renderer that returns a tiny blank image; OCR tests only care that rendering happens.
@MainActor
final class StubPageRenderer: PageRenderer {
    private(set) var renderCount = 0

    func renderImage(pageID: UUID, rect: CGRect?, scale: CGFloat, options: RenderOptions) async throws -> CGImage {
        renderCount += 1
        let ctx = CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return ctx.makeImage()!
    }

    func renderPDFPage(pageID: UUID, into ctx: CGContext, mediaBox: CGRect, options: RenderOptions) async throws {}

    func thumbnail(pageID: UUID, width: CGFloat) async -> CGImage? { nil }
}

struct SearchTestError: LocalizedError {
    var errorDescription: String? { "boom" }
}

/// In-memory library with a recognizer and renderer that can be controlled from the test.
@MainActor
struct SearchFixture {
    let services: AppServices
    let recognizer: FakeRecognizer
    let renderer: StubPageRenderer
    let service: SearchService

    init() throws {
        let recognizer = FakeRecognizer()
        let suite = UserDefaults(suiteName: "co.xanom.sheafnote.search.\(UUID().uuidString)") ?? .standard
        services = AppServices(container: try SheafnoteStore.makeContainer(inMemory: true), defaults: suite, recognizer: recognizer)
        renderer = StubPageRenderer()
        services.pageRenderer = renderer
        self.recognizer = recognizer
        service = SearchService(services: services)
    }

    @discardableResult
    func notebook(_ title: String, pages: Int = 1, kind: NotebookKind = .paged) throws -> Notebook {
        let nb = try services.library.createNotebook(title: title, kind: kind, cover: .default, template: TemplateSpec(kind: .blank),
                                                     paperSize: .a4, orientation: .portrait, paperColor: .white, in: nil)
        for _ in 1..<max(pages, 1) { try services.pages.addPage(to: nb.id, at: .end, template: nil) }
        return nb
    }

    func pages(of nb: Notebook) throws -> [Page] { try services.pages.orderedPages(of: nb.id) }

    /// Writes ink and ages the page so the OCR policy treats it as settled.
    func writeInk(on page: Page, byte: UInt8 = 1) throws {
        try services.pages.saveInk(pageID: page.id, drawingData: Data([byte]), strokeIDs: [StrokeID(rawValue: "s\(byte)")])
        page.modifiedAt = Date(timeIntervalSinceNow: -120)
        try services.context.save()
    }

    static func pdf(pages: [String]) -> Data {
        let size = CGSize(width: 612, height: 792)
        return UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: size)).pdfData { ctx in
            for text in pages {
                ctx.beginPage()
                (text as NSString).draw(at: CGPoint(x: 72, y: 72), withAttributes: [.font: UIFont.systemFont(ofSize: 32)])
            }
        }
    }
}
