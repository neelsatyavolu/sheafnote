import SwiftUI
import UIKit
import SheafnoteCore

/// Live element layer for one slot (below or above the ink). Renderers come from `ElementRendererRegistry`; an
/// element whose renderer is not registered is shown as an "unsupported" placeholder and is never dropped.
struct ElementLayerContent: View {
    let page: PageSession
    let slot: PageLayerSlot
    let host: FeatureHost

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(page.elementValues) { element in
                if let renderer = host.elementRenderers.renderer(for: element.kind) {
                    if renderer.slot == slot {
                        placed(renderer.makeView(for: element, page: page), element)
                    }
                } else if slot == .belowInk {
                    placed(AnyView(UnsupportedElementView(kind: element.kind)), element)
                }
            }
        }
        .frame(width: page.pageSize.width, height: page.pageSize.height, alignment: .topLeading)
    }

    private func placed(_ view: AnyView, _ element: ElementValue) -> some View {
        view
            .frame(width: element.frame.width, height: element.frame.height)
            .rotationEffect(.radians(element.rotation))
            .position(x: element.frame.midX, y: element.frame.midY)
            .zIndex(Double(element.zIndex))
    }
}

struct UnsupportedElementView: View {
    let kind: ElementKind

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(.secondary, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            Image(systemName: "questionmark.square.dashed").foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Unsupported \(kind.rawValue) element", tableName: "Editor"))
    }
}

/// Hosts `ElementLayerContent`. Touches pass through to the canvas except over elements that handle input
/// (study tape, links) in the layer above the ink.
final class ElementLayerView: HostedSwiftUIView<ElementLayerContent> {
    private let page: PageSession
    private let slot: PageLayerSlot
    private let host: FeatureHost

    init(page: PageSession, slot: PageLayerSlot, host: FeatureHost) {
        self.page = page
        self.slot = slot
        self.host = host
        super.init(rootView: ElementLayerContent(page: page, slot: slot, host: host))
        frame = CGRect(origin: .zero, size: page.pageSize)
        isUserInteractionEnabled = slot == .aboveInk
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard slot == .aboveInk, interactiveRegions.contains(where: { $0.contains(point) }) else { return nil }
        return super.hitTest(point, with: event)
    }

    private var interactiveRegions: [CGRect] {
        page.elementValues.compactMap { element in
            guard host.elementRenderers.renderer(for: element.kind)?.slot == .aboveInk else { return nil }
            return OrientedBoxHitTester(element: element).bounds
        }
    }
}
