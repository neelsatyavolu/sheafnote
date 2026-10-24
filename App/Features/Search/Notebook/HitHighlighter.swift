import CoreGraphics
import Foundation
import OSLog
import SheafnoteCore

/// Finds where a search hit sits on its page, as unit rectangles (origin top-left) for the result thumbnail.
/// Handwriting is located by reading the page again (the stored text has no positions), once per version of the ink.
@MainActor
final class HitHighlighter {
    private static let log = Logger(subsystem: "co.xanom.sheafnote", category: "search.highlight")
    private let services: AppServices
    private var lines: [String: [RecognizedLine]] = [:]

    init(services: AppServices) { self.services = services }

    func rects(for hit: SearchHit) async -> [CGRect] {
        guard hit.documentID.kind == .page, let page = services.pages.page(id: hit.documentID.id) else { return [] }
        var result: [CGRect] = []
        if !SnippetBuilder.matchingRanges(in: page.recognizedText, terms: hit.terms).isEmpty {
            result += HighlightGeometry.rects(for: hit.terms, in: await handwritingLines(of: page))
        }
        result += typedRects(on: page, terms: hit.terms)
        result += await pdfRects(on: page, terms: hit.terms)
        return result
    }

    private func typedRects(on page: Page, terms: [String]) -> [CGRect] {
        guard let elements = try? services.pages.elements(on: page.id) else { return [] }
        return elements.compactMap { element -> CGRect? in
            let text: String?
            switch element.kind {
            case .text: text = PayloadCodec.decode(TextPayload.self, from: element.payload)?.text
            case .link: text = PayloadCodec.decode(LinkPayload.self, from: element.payload)?.label
            default: text = nil
            }
            guard let text, !SnippetBuilder.matchingRanges(in: text, terms: terms).isEmpty else { return nil }
            return HighlightGeometry.unitRect(of: element.frame, pageSize: page.size)
        }
    }

    private func pdfRects(on page: Page, terms: [String]) async -> [CGRect] {
        guard let assetID = page.backgroundAssetID, let index = page.backgroundPageIndex,
              let data = try? await services.pages.data(for: assetID) else { return [] }
        let result = await Task.detached(priority: .userInitiated) {
            Result { try PDFTextExtractor.matchRects(in: data, pageIndex: index, terms: terms) }
        }.value
        switch result {
        case .success(let rects): return rects
        case .failure(let error):
            Self.log.info("No PDF highlight: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    private func handwritingLines(of page: Page) async -> [RecognizedLine] {
        let key = "\(page.id.uuidString)|\(page.inkHash)"
        if let cached = lines[key] { return cached }
        let options = RenderOptions(includeBackground: false, includeInk: true, includeElements: false,
                                    forExport: false, hideTape: true)
        do {
            let image = try await services.pageRenderer.renderImage(pageID: page.id, rect: nil, scale: 2, options: options)
            let languages = SearchPreferences(settings: services.settings).languages
            let recognized = try await services.recognizer.recognizeText(in: image, languages: languages).lines
            if lines.count > 60 { lines.removeAll() }
            lines[key] = recognized
            return recognized
        } catch {
            Self.log.error("Could not locate handwriting hit: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }
}
