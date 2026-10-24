import CoreGraphics
import Foundation
import SheafnoteCore

enum PageRenderError: LocalizedError {
    case pageMissing
    case renderFailed

    var errorDescription: String? {
        switch self {
        case .pageMissing: String(localized: "That page no longer exists.")
        case .renderFailed: String(localized: "The page could not be drawn.")
        }
    }
}

/// Draws paper and template only. The editor replaces it with the real renderer (ink, elements, PDF).
@MainActor
final class PlaceholderPageRenderer: PageRenderer {
    private let library: LibraryStore
    private let pages: PageStore

    init(library: LibraryStore, pages: PageStore) {
        self.library = library
        self.pages = pages
    }

    func renderImage(pageID: UUID, rect: CGRect?, scale: CGFloat, options: RenderOptions) async throws -> CGImage {
        let (spec, color, size) = try paper(for: pageID)
        guard let full = TemplateRenderer.renderImage(options.includeBackground ? spec : .blank, size: size, paper: color,
                                                      scale: scale, strings: .localized) else { throw PageRenderError.renderFailed }
        guard let rect else { return full }
        let crop = CGRect(x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale)
        guard let cropped = full.cropping(to: crop) else { throw PageRenderError.renderFailed }
        return cropped
    }

    func renderPDFPage(pageID: UUID, into ctx: CGContext, mediaBox: CGRect, options: RenderOptions) async throws {
        let (spec, color, size) = try paper(for: pageID)
        ctx.saveGState()
        ctx.translateBy(x: mediaBox.minX, y: mediaBox.minY)
        ctx.scaleBy(x: mediaBox.width / size.width, y: mediaBox.height / size.height)
        TemplateRenderer.drawFlipped(options.includeBackground ? spec : .blank, size: size, paper: color, in: ctx, strings: .localized)
        ctx.restoreGState()
    }

    func thumbnail(pageID: UUID, width: CGFloat) async -> CGImage? {
        guard let (spec, color, size) = try? paper(for: pageID), size.width > 0 else { return nil }
        return TemplateRenderer.renderImage(spec, size: size, paper: color, scale: width / size.width, strings: .localized)
    }

    private func paper(for pageID: UUID) throws -> (TemplateSpec, PaperColor, CGSize) {
        guard let page = pages.page(id: pageID), let notebook = library.notebook(id: page.notebookID) else {
            throw PageRenderError.pageMissing
        }
        return (page.template ?? notebook.template, page.paperColorOverrideValue ?? notebook.paperColorValue, page.size)
    }
}
