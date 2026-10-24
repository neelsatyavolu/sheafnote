import CoreGraphics
import SwiftUI
import UIKit
import SheafnoteCore

/// Bottom to top: paper color, template, background (PDF), below-ink elements, ink, above-ink elements, overlays.
enum PageLayerSlot: Int, Comparable, Sendable {
    case paper = 0, template = 100, background = 200, belowInk = 300, ink = 400, aboveInk = 500, overlay = 600

    static func < (l: PageLayerSlot, r: PageLayerSlot) -> Bool { l.rawValue < r.rawValue }
}

/// Value copy of what a layer needs; safe across actors.
struct PageSnapshot: Sendable {
    let pageID: UUID
    let notebookID: UUID
    let size: CGSize
    let backgroundAssetID: UUID?
    let backgroundPageIndex: Int?
    let template: TemplateSpec
    let paperColor: PaperColor
}

struct RenderOptions: Sendable {
    /// PDF background + template (export "with/without page backgrounds").
    var includeBackground: Bool
    var includeInk: Bool
    var includeElements: Bool
    /// Vector where possible.
    var forExport: Bool
    /// Study tape hidden/shown state at render time.
    var hideTape: Bool

    static let screen = RenderOptions(includeBackground: true, includeInk: true, includeElements: true,
                                      forExport: false, hideTape: false)
    static let export = RenderOptions(includeBackground: true, includeInk: true, includeElements: true,
                                      forExport: true, hideTape: false)
}

@MainActor
protocol PageLayerProvider: AnyObject {
    var slot: PageLayerSlot { get }
    /// Tie-break inside a slot.
    var order: Int { get }
    func isActive(for page: PageSnapshot) -> Bool
    /// Live layer, added to the page's container.
    func makeLayerView(for page: PageContext) -> UIView
    /// Export/thumbnail path.
    func draw(page: PageSnapshot, into ctx: CGContext, rect: CGRect, options: RenderOptions) async throws
}

@MainActor
final class PageLayerRegistry {
    private var all: [any PageLayerProvider] = []

    func register(_ provider: any PageLayerProvider) { all.append(provider) }

    func providers(for page: PageSnapshot) -> [any PageLayerProvider] {
        all.filter { $0.isActive(for: page) }
            .sorted { $0.slot == $1.slot ? $0.order < $1.order : $0.slot < $1.slot }
    }
}

@MainActor
protocol ElementRenderer: AnyObject {
    var kind: ElementKind { get }
    /// `.belowInk` or `.aboveInk`.
    var slot: PageLayerSlot { get }
    /// Live, interactive (study tape tap, link tap).
    func makeView(for element: ElementValue, page: PageContext) -> AnyView
    func draw(_ element: ElementValue, into ctx: CGContext, assets: AssetResolver, options: RenderOptions) async throws
    func hitTester(for element: ElementValue) -> any ElementHitTesting
    /// Double-tap on element.
    func beginEditing(_ element: ElementValue, page: PageContext, editor: EditorContext)
}

@MainActor
final class ElementRendererRegistry {
    private var byKind: [ElementKind: any ElementRenderer] = [:]

    func register(_ renderer: any ElementRenderer) { byKind[renderer.kind] = renderer }
    func renderer(for kind: ElementKind) -> (any ElementRenderer)? { byKind[kind] }
}

@MainActor
protocol PageRenderer: AnyObject {
    func renderImage(pageID: UUID, rect: CGRect?, scale: CGFloat, options: RenderOptions) async throws -> CGImage
    func renderPDFPage(pageID: UUID, into ctx: CGContext, mediaBox: CGRect, options: RenderOptions) async throws
    /// Cached on disk, invalidated by `Page.inkHash`.
    func thumbnail(pageID: UUID, width: CGFloat) async -> CGImage?
}

enum PageSizing: Sendable {
    case fixed(CGSize)
    case infinite(initial: CGSize)
}
