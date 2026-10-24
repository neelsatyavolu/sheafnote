import CoreGraphics
import Foundation
import PDFKit

public enum PDFTextError: LocalizedError, Equatable {
    case unreadable

    public var errorDescription: String? {
        "Sheafnote could not read the text of a PDF in this library, so it is left out of search."
    }
}

/// Reads the text layer of imported PDFs (PDFKit, on-device).
public enum PDFTextExtractor {
    /// One string per page, in page order. Scanned pages without a text layer give an empty string.
    public static func pageTexts(from data: Data) throws -> [String] {
        guard let document = PDFDocument(data: data) else { throw PDFTextError.unreadable }
        return (0..<document.pageCount).map { document.page(at: $0)?.string ?? "" }
    }

    /// Highlight rectangles for `terms` on one PDF page, in unit coordinates with origin top-left.
    public static func matchRects(in data: Data, pageIndex: Int, terms: [String]) throws -> [CGRect] {
        guard let document = PDFDocument(data: data) else { throw PDFTextError.unreadable }
        guard let page = document.page(at: pageIndex) else { return [] }
        let box = page.bounds(for: .mediaBox)
        guard box.width > 0, box.height > 0 else { return [] }
        var result: [CGRect] = []
        for term in Set(terms) {
            for selection in document.findString(term, withOptions: [.caseInsensitive, .diacriticInsensitive]) {
                guard selection.pages.contains(where: { document.index(for: $0) == pageIndex }) else { continue }
                let r = selection.bounds(for: page)
                result.append(CGRect(x: (r.minX - box.minX) / box.width, y: 1 - (r.maxY - box.minY) / box.height,
                                     width: r.width / box.width, height: r.height / box.height))
            }
        }
        return result
    }
}
