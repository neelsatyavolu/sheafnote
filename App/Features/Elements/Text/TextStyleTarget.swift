import Foundation
import SheafnoteCore

/// Remembers the last used text style, so the next new box starts the way the previous one looked.
enum TextDefaultsStore {
    private static let key = "elements.textDefaults"

    static func load(from defaults: UserDefaults = .standard) -> TextPayload {
        guard let data = defaults.data(forKey: key), var payload = PayloadCodec.decode(TextPayload.self, from: data) else {
            return TextPayload(text: "")
        }
        payload.text = ""
        payload.link = nil
        return payload
    }

    static func save(_ payload: TextPayload, to defaults: UserDefaults = .standard) {
        var style = payload
        style.text = ""
        style.link = nil
        defaults.set(PayloadCodec.encode(style), forKey: key)
    }
}

/// The text box the options row acts on: the one being edited, else the selected one, else the defaults for new boxes.
@MainActor
struct TextStyleTarget {
    let session: TextEditSession
    let editor: EditorContext

    private var selectedElement: ElementValue? {
        guard let page = editor.currentPage,
              let element = ElementSelecting.selectedElement(on: page, editor: editor), element.kind == .text else { return nil }
        return element
    }

    /// True when a change reaches an existing box (editing or selected), false when it only sets the defaults.
    var hasTarget: Bool { session.isEditing || selectedElement != nil }

    var payload: TextPayload {
        if session.isEditing { return session.working }
        if let element = selectedElement, let payload = element.decoded(TextPayload.self) { return payload }
        return TextDefaultsStore.load()
    }

    func apply(_ change: (inout TextPayload) -> Void) {
        var style = payload
        change(&style)
        TextDefaultsStore.save(style)
        if session.isEditing {
            session.working = withText(style, from: session.working)
        } else if let page = editor.currentPage, let element = selectedElement {
            let updated = withText(style, from: element.decoded(TextPayload.self) ?? style)
            do {
                try page.elements.update(id: element.id, undoName: LocalizedStringResource("Change Text Style", table: "Elements")) {
                    $0.payload = PayloadCodec.encode(updated)
                }
            } catch {
                ElementErrors.report(error, editor: editor)
            }
        }
    }

    private func withText(_ style: TextPayload, from source: TextPayload) -> TextPayload {
        var result = style
        result.text = source.text
        result.link = source.link
        return result
    }
}
