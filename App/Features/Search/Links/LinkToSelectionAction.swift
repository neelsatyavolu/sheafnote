import SwiftUI
import SheafnoteCore

/// Selection action "Link to…": makes the selected ink, image or text open a page, notebook or web address when tapped.
/// A selected text box keeps the link in its own payload; anything else gets a link element over the selection.
@MainActor
final class LinkToSelectionAction: SelectionAction {
    let id = "search.linkTo"
    let title = LocalizedStringResource("Link to…", table: "Search")
    let symbolName = "link"
    let order = 70

    func isEnabled(for selection: SelectionModel, editor: EditorContext) -> Bool {
        !selection.isEmpty && selection.pageID != nil
    }

    func perform(selection: SelectionModel, page: any PageContext, editor: EditorContext) async throws {
        let strokeCount = selection.strokeIDs.count
        let elementIDs = selection.elementIDs
        let bounds = selection.bounds
        guard let choice = await askForTarget(page: page, editor: editor) else { return }
        try Self.apply(choice, strokeCount: strokeCount, elementIDs: elementIDs, bounds: bounds, page: page)
    }

    private func askForTarget(page: any PageContext, editor: EditorContext) async -> LinkChoice? {
        await withCheckedContinuation { continuation in
            let once = OnceResume(continuation)
            editor.present(EditorSheet(detents: [.large]) {
                AnyView(LinkPickerSheet(services: editor.services, notebookID: page.notebookID,
                                        onChoose: { once.resume($0) }, onCancel: { once.resume(nil) }))
            })
        }
    }

    /// Chooses between updating the one selected link or text box and creating a link element.
    static func apply(_ choice: LinkChoice, strokeCount: Int, elementIDs: Set<UUID>, bounds: CGRect?,
                      page: any PageContext) throws {
        let selected = page.elements.all.filter { elementIDs.contains($0.id) }
        if strokeCount == 0, selected.count == 1, let only = selected.first {
            switch only.kind {
            case .link:
                try page.elements.update(id: only.id, undoName: "Edit Link") {
                    $0.payload = PayloadCodec.encode(LinkPayload(target: choice.target, label: choice.label))
                }
                return
            case .text:
                try setTextLink(choice.target, on: only, page: page)
                return
            default:
                break
            }
        }
        guard let bounds, bounds.width > 0, bounds.height > 0 else { throw LinkError.nothingSelected }
        let top = (page.elements.all.map(\.zIndex).max() ?? 0) + 1
        let element = ElementValue(pageID: page.pageID, kind: .link, frame: bounds.insetBy(dx: -4, dy: -4), zIndex: top,
                                   payload: PayloadCodec.encode(LinkPayload(target: choice.target, label: choice.label)))
        try page.elements.add(element, undoName: "Add Link")
    }

    private static func setTextLink(_ target: LinkTarget, on element: ElementValue, page: any PageContext) throws {
        guard var payload = PayloadCodec.decode(TextPayload.self, from: element.payload) else { throw LinkError.unreadableText }
        payload.link = target
        try page.elements.update(id: element.id, undoName: "Add Link") { $0.payload = PayloadCodec.encode(payload) }
    }
}

enum LinkError: LocalizedError {
    case nothingSelected
    case unreadableText

    var errorDescription: String? {
        switch self {
        case .nothingSelected: String(localized: "Select something first, then choose Link to…", table: "Search")
        case .unreadableText: String(localized: "This text box can't take a link because its contents couldn't be read.", table: "Search")
        }
    }
}

/// Resumes a checked continuation exactly once, however many times the sheet reports back.
@MainActor
private final class OnceResume {
    private var continuation: CheckedContinuation<LinkChoice?, Never>?

    init(_ continuation: CheckedContinuation<LinkChoice?, Never>) { self.continuation = continuation }

    func resume(_ value: LinkChoice?) {
        continuation?.resume(returning: value)
        continuation = nil
    }
}
