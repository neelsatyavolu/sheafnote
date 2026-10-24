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

/// Cover with a notebook silhouette: rounded outer corners and a soft shadow.
struct NotebookCoverView: View {
    let cover: CoverSpec

    var body: some View {
        CoverArtView(definition: cover.definition)
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 2, bottomLeadingRadius: 2,
                                              bottomTrailingRadius: 8, topTrailingRadius: 8))
            .shadow(color: .black.opacity(0.25), radius: 5, x: 0, y: 3)
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
