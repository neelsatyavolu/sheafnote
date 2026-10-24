import SwiftUI
import SheafnoteCore

/// Renders `.link` elements: an invisible-in-export, faintly tinted hot spot over the linked ink or text. Tapping it
/// follows the link; long-press offers edit and remove. Links are drawn in the layer above the ink.
@MainActor
final class LinkElementRenderer: ElementRenderer {
    let kind = ElementKind.link
    let slot = PageLayerSlot.aboveInk
    private unowned let host: FeatureHost

    init(host: FeatureHost) { self.host = host }

    func makeView(for element: ElementValue, page: PageContext) -> AnyView {
        AnyView(LinkElementView(element: element, page: page, host: host))
    }

    /// Links are for the screen only: exported pages and thumbnails show just the content underneath.
    func draw(_ element: ElementValue, into ctx: CGContext, assets: AssetResolver, options: RenderOptions) async throws {}

    func hitTester(for element: ElementValue) -> any ElementHitTesting { OrientedBoxHitTester(element: element) }

    func beginEditing(_ element: ElementValue, page: PageContext, editor: EditorContext) {
        LinkEditing.present(element: element, page: page, editor: editor)
    }
}

struct LinkElementView: View {
    let element: ElementValue
    let page: PageContext
    let host: FeatureHost

    private var payload: LinkPayload? { PayloadCodec.decode(LinkPayload.self, from: element.payload) }

    var body: some View {
        Rectangle()
            .fill(Color.accentColor.opacity(0.07))
            .overlay(alignment: .bottom) { Rectangle().fill(Color.accentColor.opacity(0.7)).frame(height: 1.5) }
            .contentShape(Rectangle())
            .onTapGesture { follow() }
            .contextMenu {
                Button { edit() } label: { Label { Text("Edit Link…", tableName: "Search") } icon: { Image(systemName: "link") } }
                Button(role: .destructive) { remove() } label: {
                    Label { Text("Remove Link", tableName: "Search") } icon: { Image(systemName: "link.badge.minus") }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityHint(Text("Opens the link", tableName: "Search"))
            .accessibilityAddTraits(.isLink)
            .accessibilityIdentifier("search.link.element")
    }

    private var accessibilityLabel: Text {
        guard let payload else { return Text("Link", tableName: "Search") }
        if payload.label.isEmpty { return Text("Link", tableName: "Search") }
        return Text("Link to \(payload.label)", tableName: "Search")
    }

    private func follow() {
        guard let target = payload?.target else { return }
        let notebookID = page.notebookID
        Task {
            if case .failed(let message) = await LinkFollower.follow(target, from: notebookID, host: host) {
                NotebookNavigator.openEditor(for: notebookID, host: host)?.showToast(message)
            }
        }
    }

    private func edit() {
        guard let editor = NotebookNavigator.openEditor(for: page.notebookID, host: host) else { return }
        LinkEditing.present(element: element, page: page, editor: editor)
    }

    private func remove() {
        do { try page.elements.remove(ids: [element.id], undoName: "Remove Link") } catch {
            NotebookNavigator.openEditor(for: page.notebookID, host: host)?
                .showToast(LocalizedStringResource("Couldn't remove the link: \(error.localizedDescription)", table: "Search"))
        }
    }
}

/// Re-targets an existing link element through the same picker used to create links.
@MainActor
enum LinkEditing {
    static func present(element: ElementValue, page: PageContext, editor: EditorContext) {
        let elementID = element.id
        let services = editor.services
        editor.present(EditorSheet(detents: [.large]) {
            AnyView(LinkPickerSheet(services: services, notebookID: page.notebookID, onChoose: { choice in
                do {
                    try page.elements.update(id: elementID, undoName: "Edit Link") { value in
                        value.payload = PayloadCodec.encode(LinkPayload(target: choice.target, label: choice.label))
                    }
                } catch {
                    editor.showToast(LocalizedStringResource("Couldn't change the link: \(error.localizedDescription)", table: "Search"))
                }
            }, onCancel: {}))
        })
    }
}
