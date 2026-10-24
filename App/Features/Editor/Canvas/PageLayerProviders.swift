import PencilKit
import SwiftUI
import UIKit
import SheafnoteCore

/// Contexts passed to `draw(page:into:rect:options:)` have a top-left origin in page points (the editor's renderer sets that up).

@MainActor
final class PaperLayerProvider: PageLayerProvider {
    let slot = PageLayerSlot.paper
    let order = 0

    func isActive(for page: PageSnapshot) -> Bool { true }

    func makeLayerView(for page: PageContext) -> UIView {
        let view = UIView(frame: CGRect(origin: .zero, size: page.pageSize))
        if let page = page as? PageSession {
            view.backgroundColor = UIColor(cgColor: PaperPalette.palette(for: page.snapshot.paperColor).paper.cgColor)
        }
        view.isUserInteractionEnabled = false
        return view
    }

    func draw(page: PageSnapshot, into ctx: CGContext, rect: CGRect, options: RenderOptions) async throws {
        ctx.setFillColor(PaperPalette.palette(for: page.paperColor).paper.cgColor)
        ctx.fill(rect)
    }
}

@MainActor
final class TemplateLayerProvider: PageLayerProvider {
    let slot = PageLayerSlot.template
    let order = 0

    func isActive(for page: PageSnapshot) -> Bool { page.template.kind != .blank }

    func makeLayerView(for page: PageContext) -> UIView {
        guard let page = page as? PageSession else { return UIView() }
        let snapshot = page.snapshot
        return TemplateTiledView(content: TemplateContent(spec: snapshot.template, paper: snapshot.paperColor,
                                                          size: snapshot.size, strings: .localized))
    }

    func draw(page: PageSnapshot, into ctx: CGContext, rect: CGRect, options: RenderOptions) async throws {
        TemplateRenderer.draw(page.template, size: page.size, paper: page.paperColor, in: ctx, includePaper: false, strings: .localized)
    }
}

/// The ink layer is the page's `PKCanvasView`. For export it draws the saved drawing as an image.
@MainActor
final class InkLayerProvider: PageLayerProvider {
    let slot = PageLayerSlot.ink
    let order = 0
    private unowned let host: FeatureHost

    init(host: FeatureHost) { self.host = host }

    func isActive(for page: PageSnapshot) -> Bool { true }

    func makeLayerView(for page: PageContext) -> UIView {
        guard let page = page as? PageSession else { return UIView() }
        return page.makeCanvas()
    }

    func draw(page: PageSnapshot, into ctx: CGContext, rect: CGRect, options: RenderOptions) async throws {
        guard let data = host.services.pages.inkData(pageID: page.pageID), !data.isEmpty else { return }
        let drawing = try PKDrawing(data: data)
        guard !drawing.strokes.isEmpty else { return }
        let deviceScale = max(1, hypot(ctx.ctm.a, ctx.ctm.b))
        let scale = options.forExport ? max(deviceScale, 3) : deviceScale
        var image: UIImage?
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            image = drawing.image(from: rect, scale: scale)
        }
        guard let image else { return }
        UIGraphicsPushContext(ctx)
        image.draw(in: rect)
        UIGraphicsPopContext()
    }
}

@MainActor
final class ElementLayerProvider: PageLayerProvider {
    let slot: PageLayerSlot
    let order = 0
    private unowned let host: FeatureHost

    init(slot: PageLayerSlot, host: FeatureHost) {
        self.slot = slot
        self.host = host
    }

    func isActive(for page: PageSnapshot) -> Bool { true }

    func makeLayerView(for page: PageContext) -> UIView {
        guard let page = page as? PageSession else { return UIView() }
        return ElementLayerView(page: page, slot: slot, host: host)
    }

    func draw(page: PageSnapshot, into ctx: CGContext, rect: CGRect, options: RenderOptions) async throws {
        let services = host.services
        for element in try services.pages.elements(on: page.pageID) {
            guard let renderer = host.elementRenderers.renderer(for: element.kind), renderer.slot == slot else { continue }
            try await renderer.draw(element, into: ctx, assets: services.pages, options: options)
        }
    }
}
