import SheafnoteCore
import SwiftUI
import UIKit

/// One block of a text document: a marker (bullet, number, checkbox) and an editable field, or a picture.
struct TextBlockRow: View {
    let model: TextDocumentModel
    let block: RichTextBlock
    let index: Int
    let number: Int?
    var focus: FocusState<UUID?>.Binding

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            marker
            if block.kind == .image {
                TextDocumentImage(services: model.services, assetID: block.assetID)
            } else {
                field
            }
        }
        .contextMenu {
            Button(role: .destructive) { model.change { $0.removingBlock(block.id) } } label: {
                Label { Text("Delete Block", tableName: "DocTypes") } icon: { Image(systemName: "trash") }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var field: some View {
        TextField(text: Binding(get: { block.text }, set: { model.edit(text: $0, in: block.id) }), axis: .vertical) {
            Text(placeholder, tableName: "DocTypes")
        }
        .font(font)
        .fontWeight(block.bold ? .bold : nil)
        .italic(block.italic)
        .underline(block.underline)
        .strikethrough(block.kind == .checklist && block.checked)
        .foregroundStyle(block.kind == .checklist && block.checked ? .secondary : .primary)
        .focused(focus, equals: block.id)
        .disabled(!model.isEditable)
        .accessibilityLabel(Text(accessibilityName))
        .accessibilityIdentifier("textdoc.field.\(index)")
    }

    @ViewBuilder private var marker: some View {
        switch block.kind {
        case .bullet:
            Text("•").font(font).accessibilityHidden(true)
        case .numbered:
            Text("\(number ?? 1).").font(font).monospacedDigit().accessibilityHidden(true)
        case .checklist:
            Button { model.change { $0.togglingChecked(for: block.id) } } label: {
                Image(systemName: block.checked ? "checkmark.circle.fill" : "circle")
                    .font(font).foregroundStyle(block.checked ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Checkbox", tableName: "DocTypes"))
            .accessibilityValue(Text(block.checked ? "Checked" : "Not checked", tableName: "DocTypes"))
            .accessibilityIdentifier("textdoc.check.\(index)")
        default:
            EmptyView()
        }
    }

    private var font: Font {
        switch block.kind {
        case .heading1: .title.bold()
        case .heading2: .title2.bold()
        case .heading3: .title3.bold()
        default: .body
        }
    }

    private var placeholder: LocalizedStringKey {
        index == 0 && block.kind == .paragraph ? "Start typing" : ""
    }

    private var accessibilityName: LocalizedStringResource {
        switch block.kind {
        case .heading1: LocalizedStringResource("Title", table: "DocTypes")
        case .heading2: LocalizedStringResource("Heading", table: "DocTypes")
        case .heading3: LocalizedStringResource("Subheading", table: "DocTypes")
        case .bullet: LocalizedStringResource("Bulleted item", table: "DocTypes")
        case .numbered: LocalizedStringResource("Numbered item", table: "DocTypes")
        case .checklist: LocalizedStringResource("Checklist item", table: "DocTypes")
        default: LocalizedStringResource("Paragraph", table: "DocTypes")
        }
    }
}

/// A picture inserted in a text document, loaded from the notebook's assets.
struct TextDocumentImage: View {
    let services: AppServices
    let assetID: UUID?
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFit().frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel(Text("Picture", tableName: "DocTypes"))
            } else if failed {
                Label { Text("This picture can't be shown.", tableName: "DocTypes") } icon: { Image(systemName: "photo") }
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
            }
        }
        .task(id: assetID) {
            guard let assetID else { failed = true; return }
            do {
                let data = try await services.pages.data(for: assetID)
                if let decoded = UIImage(data: data) { image = decoded } else { failed = true }
            } catch {
                failed = true
            }
        }
    }
}
