import CoreGraphics
import SwiftUI
import UIKit
import SheafnoteCore

/// Shows an error from an element operation. Uses the editor's alert when it is the standard editor session, so a
/// failure is never silent; falls back to a toast.
@MainActor
enum ElementErrors {
    static func report(_ error: Error, editor: EditorContext) {
        if let session = editor as? NotebookSession {
            session.report(error)
        } else {
            let message = error.localizedDescription
            editor.showToast(LocalizedStringResource("\(message)", table: "Elements"))
        }
    }
}

extension ElementErrors {
    /// For views that only know their page (not the editor), such as the tape tap.
    static func report(_ error: Error, page: any PageContext) {
        guard let session = page as? PageSession else {
            assertionFailure("Element error without an editor: \(error)")
            return
        }
        session.notebook.report(error)
    }
}

/// Finding, selecting and ordering elements through the shared selection model.
@MainActor
enum ElementSelecting {
    /// The element a hit at `point` should pick: aboveInk elements first, then by z-order, topmost wins.
    static func topElement(at point: CGPoint, on page: any PageContext, host: FeatureHost,
                           kinds: Set<ElementKind>? = nil) -> ElementValue? {
        page.elements.all
            .filter { kinds?.contains($0.kind) ?? true }
            .filter { hitTester(for: $0, host: host).contains(point: point) }
            .max { lhs, rhs in
                let l = slotRank(lhs, host: host), r = slotRank(rhs, host: host)
                return l == r ? lhs.zIndex < rhs.zIndex : l < r
            }
    }

    static func hitTester(for element: ElementValue, host: FeatureHost) -> any ElementHitTesting {
        host.elementRenderers.renderer(for: element.kind)?.hitTester(for: element) ?? OrientedBoxHitTester(element: element)
    }

    static func select(_ element: ElementValue, on page: any PageContext, editor: EditorContext, host: FeatureHost) {
        let bounds = hitTester(for: element, host: host).bounds
        editor.selection.select(pageID: page.pageID, strokeIDs: [], elementIDs: [element.id], bounds: bounds)
    }

    /// The single selected element on `page`, if exactly one element (and no ink) is selected.
    static func selectedElement(on page: any PageContext, editor: EditorContext) -> ElementValue? {
        let selection = editor.selection
        guard selection.pageID == page.pageID, selection.strokeIDs.isEmpty, selection.elementIDs.count == 1,
              let id = selection.elementIDs.first else { return nil }
        return page.elements.all.first { $0.id == id }
    }

    /// Re-reads the element's bounds after it changed, so the selection frame follows edits.
    static func refreshSelection(for id: UUID, on page: any PageContext, editor: EditorContext, host: FeatureHost) {
        guard editor.selection.elementIDs == [id], let element = page.elements.all.first(where: { $0.id == id }) else { return }
        select(element, on: page, editor: editor, host: host)
    }

    private static func slotRank(_ element: ElementValue, host: FeatureHost) -> Int {
        host.elementRenderers.renderer(for: element.kind)?.slot == .aboveInk ? 1 : 0
    }
}

/// Drawing helpers shared by the element renderers' export paths.
enum ElementDrawing {
    /// Runs `body` with the context rotated about the element's centre.
    static func withRotation(_ element: ElementValue, in ctx: CGContext, _ body: () -> Void) {
        ctx.saveGState()
        defer { ctx.restoreGState() }
        if element.rotation != 0 {
            ctx.translateBy(x: element.frame.midX, y: element.frame.midY)
            ctx.rotate(by: element.rotation)
            ctx.translateBy(x: -element.frame.midX, y: -element.frame.midY)
        }
        body()
    }

    /// Draws `image` (a normal, upright CGImage) into `rect` of a top-left-origin context.
    static func draw(_ image: CGImage, in rect: CGRect, ctx: CGContext) {
        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.translateBy(x: rect.minX, y: rect.maxY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(origin: .zero, size: rect.size))
    }
}

extension ElementValue {
    func decoded<T: Decodable>(_ type: T.Type) -> T? { PayloadCodec.decode(type, from: payload) }

    func replacingPayload<T: Encodable>(_ payload: T) -> ElementValue {
        var copy = self
        copy.payload = PayloadCodec.encode(payload)
        return copy
    }
}
