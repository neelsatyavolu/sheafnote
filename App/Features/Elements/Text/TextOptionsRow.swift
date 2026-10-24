import SwiftUI
import SheafnoteCore

/// Options row of the text tool: font, size, color, bold/italic/underline, alignment and background color.
struct TextOptionsRow: View {
    let session: TextEditSession
    let editor: EditorContext

    private var target: TextStyleTarget { TextStyleTarget(session: session, editor: editor) }

    var body: some View {
        let payload = target.payload
        HStack(spacing: 10) {
            fontMenu(payload)
            sizeControl(payload)
            ColorPicker(selection: color(\.colorHex, payload), supportsOpacity: false) {
                Text("Text color", tableName: "Elements")
            }
            .labelsHidden()
            .accessibilityIdentifier("elements.text.color")
            styleToggle("bold", String(localized: "Bold", table: "Elements"), payload.isBold) { $0.isBold.toggle() }
            styleToggle("italic", String(localized: "Italic", table: "Elements"), payload.isItalic) { $0.isItalic.toggle() }
            styleToggle("underline", String(localized: "Underline", table: "Elements"), payload.isUnderlined) { $0.isUnderlined.toggle() }
            alignmentMenu(payload)
            backgroundControl(payload)
            if !target.hasTarget {
                Text("Tap the page to add a text box", tableName: "Elements")
                    .font(.footnote).foregroundStyle(Theme.inkMuted).lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .optionsCapsule()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("elements.text.options")
    }

    // MARK: Controls

    private func fontMenu(_ payload: TextPayload) -> some View {
        Menu {
            ForEach(TextStyling.fontChoices) { choice in
                Button { target.apply { $0.fontName = choice.id } } label: {
                    if choice.id == payload.fontName { Label(choice.displayName, systemImage: "checkmark") } else { Text(choice.displayName) }
                }
            }
        } label: {
            Label(TextStyling.fontChoices.first { $0.id == payload.fontName }?.displayName ?? payload.fontName,
                  systemImage: "textformat")
                .lineLimit(1)
        }
        .accessibilityLabel(Text("Font", tableName: "Elements"))
        .accessibilityValue(payload.fontName)
        .accessibilityIdentifier("elements.text.font")
    }

    private func sizeControl(_ payload: TextPayload) -> some View {
        HStack(spacing: 4) {
            Button { target.apply { $0.fontSize = step($0.fontSize, by: -1) } } label: { Image(systemName: "minus.circle") }
                .accessibilityLabel(Text("Smaller text", tableName: "Elements"))
            Menu {
                ForEach(TextStyling.sizes, id: \.self) { size in
                    Button(String(Int(size))) { target.apply { $0.fontSize = size } }
                }
            } label: {
                Text("\(Int(payload.fontSize))").monospacedDigit().frame(minWidth: 28)
            }
            .accessibilityLabel(Text("Font size", tableName: "Elements"))
            .accessibilityValue("\(Int(payload.fontSize))")
            Button { target.apply { $0.fontSize = step($0.fontSize, by: 1) } } label: { Image(systemName: "plus.circle") }
                .accessibilityLabel(Text("Larger text", tableName: "Elements"))
        }
        .accessibilityElement(children: .contain)
    }

    private func styleToggle(_ symbol: String, _ label: String, _ isOn: Bool, _ change: @escaping (inout TextPayload) -> Void) -> some View {
        Button { target.apply(change) } label: {
            Image(systemName: symbol)
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 8).fill(isOn ? Theme.accent.opacity(0.2) : .clear))
        }
        .accessibilityLabel(Text(label))
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .accessibilityIdentifier("elements.text.\(symbol)")
    }

    private func alignmentMenu(_ payload: TextPayload) -> some View {
        Menu {
            ForEach(TextAlignmentValue.allCases, id: \.self) { value in
                Button { target.apply { $0.alignment = value } } label: {
                    Label(alignmentTitle(value), systemImage: alignmentSymbol(value))
                }
            }
        } label: {
            Image(systemName: alignmentSymbol(payload.alignment)).frame(width: 32, height: 32)
        }
        .accessibilityLabel(Text("Alignment", tableName: "Elements"))
        .accessibilityValue(alignmentTitle(payload.alignment))
    }

    private func backgroundControl(_ payload: TextPayload) -> some View {
        HStack(spacing: 4) {
            Button {
                target.apply { $0.backgroundHex = $0.backgroundHex == nil ? "#FFF3B0" : nil }
            } label: {
                Image(systemName: payload.backgroundHex == nil ? "rectangle" : "rectangle.fill")
                    .frame(width: 32, height: 32)
            }
            .accessibilityLabel(Text("Background fill", tableName: "Elements"))
            .accessibilityValue(payload.backgroundHex == nil ? String(localized: "Off", table: "Elements") : String(localized: "On", table: "Elements"))
            if let hex = payload.backgroundHex {
                ColorPicker(selection: Binding(get: { Color(hex: hex) }, set: { new in target.apply { $0.backgroundHex = new.hexString } }),
                            supportsOpacity: false) { Text("Background color", tableName: "Elements") }
                    .labelsHidden()
            }
        }
    }

    // MARK: Helpers

    private func color(_ keyPath: WritableKeyPath<TextPayload, String>, _ payload: TextPayload) -> Binding<Color> {
        Binding(get: { Color(hex: payload[keyPath: keyPath]) },
                set: { new in target.apply { $0[keyPath: keyPath] = new.hexString } })
    }

    private func step(_ size: Double, by direction: Int) -> Double {
        let sizes = TextStyling.sizes
        if direction > 0 { return sizes.first { $0 > size } ?? min(size + 8, 400) }
        return sizes.last { $0 < size } ?? max(size - 1, 6)
    }

    private func alignmentSymbol(_ value: TextAlignmentValue) -> String {
        switch value {
        case .leading: "text.alignleft"
        case .center: "text.aligncenter"
        case .trailing: "text.alignright"
        }
    }

    private func alignmentTitle(_ value: TextAlignmentValue) -> String {
        switch value {
        case .leading: String(localized: "Left", table: "Elements")
        case .center: String(localized: "Center", table: "Elements")
        case .trailing: String(localized: "Right", table: "Elements")
        }
    }
}
