import SwiftUI
import UIKit
import SheafnoteCore

/// Read-only rendering of a text box. A non-editable UITextView keeps line breaking identical to the editor.
struct TextBoxDisplayView: UIViewRepresentable {
    let payload: TextPayload

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        Self.configureCommon(view)
        view.isEditable = false
        view.isSelectable = false
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        view.attributedText = TextStyling.attributed(payload)
        view.backgroundColor = TextStyling.backgroundColor(for: payload) ?? .clear
    }

    static func configureCommon(_ view: UITextView) {
        view.isScrollEnabled = false
        view.textContainerInset = UIEdgeInsets(top: TextBoxLayout.padding, left: TextBoxLayout.padding,
                                               bottom: TextBoxLayout.padding, right: TextBoxLayout.padding)
        view.textContainer.lineFragmentPadding = 0
        view.layer.cornerRadius = 3
        view.clipsToBounds = true
        view.overrideUserInterfaceStyle = .light
    }
}

/// The live text box element (shown below the ink).
struct TextElementView: View {
    let element: ElementValue
    let session: TextEditSession

    var body: some View {
        if let payload = element.decoded(TextPayload.self) {
            TextBoxDisplayView(payload: payload)
                .opacity(session.isEditing(element.id) ? 0 : 1)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(payload.text.isEmpty ? String(localized: "Empty text box", table: "Elements") : payload.text))
                .accessibilityAddTraits(.isStaticText)
        } else {
            Color.clear
        }
    }
}

/// The editable text view of the box being edited. It writes typed text into the session's working copy.
struct TextBoxEditingView: UIViewRepresentable {
    let session: TextEditSession

    func makeCoordinator() -> Coordinator { Coordinator(session: session) }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        TextBoxDisplayView.configureCommon(view)
        view.isEditable = true
        view.delegate = context.coordinator
        view.autocorrectionType = .default
        view.attributedText = TextStyling.attributed(session.working)
        view.typingAttributes = TextStyling.attributes(for: session.working)
        view.backgroundColor = TextStyling.backgroundColor(for: session.working) ?? UIColor.white.withAlphaComponent(0.9)
        view.accessibilityLabel = String(localized: "Text box", table: "Elements")
        DispatchQueue.main.async { view.becomeFirstResponder() }
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        let payload = session.working
        view.backgroundColor = TextStyling.backgroundColor(for: payload) ?? UIColor.white.withAlphaComponent(0.9)
        // Typing already keeps the view and the model in step; only a style change (options row) needs a re-style.
        let key = styleKey(payload)
        guard context.coordinator.lastStyleKey != key else { return }
        context.coordinator.lastStyleKey = key
        let selected = view.selectedRange
        view.attributedText = TextStyling.attributed(payload)
        view.typingAttributes = TextStyling.attributes(for: payload)
        view.selectedRange = selected
    }

    private func styleKey(_ payload: TextPayload) -> TextPayload {
        var copy = payload
        copy.text = ""
        return copy
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {
        let session: TextEditSession
        var lastStyleKey: TextPayload

        init(session: TextEditSession) {
            self.session = session
            var key = session.working
            key.text = ""
            lastStyleKey = key
        }

        func textViewDidChange(_ textView: UITextView) {
            session.working.text = textView.text
        }
    }
}
