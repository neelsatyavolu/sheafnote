import SwiftUI
import SheafnoteCore

/// A cover drawn by Core's vector renderer. Portrait 3:4.
struct CoverArtView: View {
    let definition: CoverDefinition

    var body: some View {
        Canvas { context, size in
            context.withCGContext { CoverRenderer.draw(definition, size: size, in: $0) }
        }
        .aspectRatio(3.0 / 4.0, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

/// Cover with a notebook silhouette: rounded open edge, a cream label plate holding the serif title, and a warm shadow.
/// The title is real text; the library also shows it under the cover.
struct NotebookCoverView: View {
    let cover: CoverSpec
    var title: String?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        CoverArtView(definition: cover.definition)
            .overlay { CoverPlate(title: title) }
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 3, bottomLeadingRadius: 3,
                                              bottomTrailingRadius: Theme.Radius.cover,
                                              topTrailingRadius: Theme.Radius.cover, style: .continuous))
            .shadow(color: colorScheme == .dark ? Color.black.opacity(0.45) : Theme.shadowColor, radius: 7, x: 0, y: 4)
    }
}

/// The cream plate across the cover. Narrow covers (list thumbnails) show the plate without text.
private struct CoverPlate: View {
    let title: String?

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let plateW = w * 0.68
            let fill = Color(cgColor: CoverPlateStyle.fill.cgColor)
            let ink = Color(cgColor: CoverPlateStyle.ink.cgColor)
            let corner = max(1.5, w * 0.02)
            ZStack {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(fill)
                    .overlay(RoundedRectangle(cornerRadius: corner, style: .continuous).stroke(ink.opacity(0.14), lineWidth: 0.5))
                    .shadow(color: ink.opacity(0.18), radius: 1, x: 0, y: 1)
                if let title, !title.isEmpty, w >= 70 {
                    Text(title)
                        .font(.system(size: w * 0.1, weight: .semibold, design: .serif))
                        .foregroundStyle(ink)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .minimumScaleFactor(0.6)
                        .padding(.horizontal, w * 0.04)
                }
            }
            .frame(width: plateW, height: h * 0.25)
            .position(x: w * 0.16 + plateW / 2, y: h * 0.42)
        }
        .accessibilityHidden(true)
    }
}

/// A scaled-down page of paper with its template.
struct PaperPreviewView: View {
    let template: TemplateSpec
    let color: PaperColor
    var pageSize: CGSize = PaperSize.a4.portraitSize

    var body: some View {
        Canvas { context, size in
            let scale = size.width / pageSize.width
            context.withCGContext { cg in
                cg.scaleBy(x: scale, y: scale)
                TemplateRenderer.draw(template, size: pageSize, paper: color, in: cg, strings: .localized)
            }
        }
        .aspectRatio(pageSize.width / pageSize.height, contentMode: .fit)
        .overlay(Rectangle().stroke(.separator, lineWidth: 0.5))
        .accessibilityHidden(true)
    }
}
