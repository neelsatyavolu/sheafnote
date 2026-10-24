import SwiftUI
import SheafnoteCore

/// Paper type chips, a carousel of variants, and the paper color. Shared by the new-notebook sheet and
/// the editor's "change page template" sheet.
struct TemplatePickerView: View {
    @Binding var template: TemplateSpec
    @Binding var paperColor: PaperColor
    var pageSize: CGSize = PaperSize.a4.portraitSize

    @State private var category: TemplateCategory
    @ScaledMetric private var previewWidth: CGFloat = 96

    init(template: Binding<TemplateSpec>, paperColor: Binding<PaperColor>, pageSize: CGSize = PaperSize.a4.portraitSize) {
        _template = template
        _paperColor = paperColor
        self.pageSize = pageSize
        _category = State(initialValue: template.wrappedValue.kind.category)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            categoryChips
            carousel
            Picker("Paper Color", selection: $paperColor) {
                ForEach(PaperColor.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("paper.color")
        }
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(TemplateCategory.allCases, id: \.self) { cat in
                    Button {
                        category = cat
                        if template.kind.category != cat, let first = cat.kinds.first { template = TemplateSpec(kind: first) }
                    } label: {
                        Text(cat.title).font(.subheadline.weight(.medium))
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .background(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                                .fill(category == cat ? Theme.accent : Theme.paperRaised))
                            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                                .stroke(Theme.rule, lineWidth: category == cat ? 0 : 1))
                            .foregroundStyle(category == cat ? Theme.paper : Theme.ink)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(category == cat ? .isSelected : [])
                    .accessibilityIdentifier("paper.category.\(cat.rawValue)")
                }
            }
        }
    }

    private var carousel: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 14) {
                ForEach(category.kinds, id: \.self) { kind in
                    Button { template = TemplateSpec(kind: kind) } label: {
                        VStack(spacing: 6) {
                            PaperPreviewView(template: TemplateSpec(kind: kind), color: paperColor, pageSize: pageSize)
                                .frame(width: previewWidth)
                                .shadow(color: Theme.shadowColor, radius: 6, y: 3)
                                .padding(3)
                                .overlay(RoundedRectangle(cornerRadius: 4)
                                    .stroke(Theme.accent, lineWidth: template.kind == kind ? 3 : 0))
                            Text(kind.title).font(.caption).multilineTextAlignment(.center)
                                .foregroundStyle(template.kind == kind ? Theme.ink : Theme.inkMuted)
                                .fontWeight(template.kind == kind ? .semibold : .regular)
                                .frame(width: previewWidth)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(kind.title))
                    .accessibilityAddTraits(template.kind == kind ? [.isButton, .isSelected] : .isButton)
                    .accessibilityIdentifier("paper.\(kind.rawValue)")
                }
            }
            .padding(.vertical, 4)
        }
        .scrollClipDisabled()
    }
}
