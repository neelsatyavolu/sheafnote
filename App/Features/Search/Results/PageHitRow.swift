import SwiftUI
import SheafnoteCore

/// A page result: thumbnail with the hits highlighted, where it is, and the matching text.
struct PageHitRow: View {
    let result: PageResult
    let showsNotebookTitle: Bool
    let services: AppServices
    let highlighter: HitHighlighter

    @ScaledMetric(relativeTo: .body) private var thumbnailWidth: CGFloat = 84

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            HighlightedThumbnail(result: result, services: services, highlighter: highlighter)
                .frame(width: thumbnailWidth)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                if showsNotebookTitle {
                    Text(result.notebookTitle).font(Theme.title(.headline)).foregroundStyle(Theme.ink).lineLimit(2)
                }
                Text("Page \(result.pageNumber)", tableName: "Search")
                    .font(showsNotebookTitle ? .subheadline : .headline)
                    .foregroundStyle(showsNotebookTitle ? Theme.inkMuted : Theme.ink)
                Text(SnippetText.attributed(result.hit.snippet)).font(.callout).foregroundStyle(Theme.ink).lineLimit(4)
                Text(fieldLabel, tableName: "Search").font(.caption).foregroundStyle(Theme.inkMuted)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .paperCard()
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isButton)
    }

    private var fieldLabel: LocalizedStringKey {
        switch result.hit.field {
        case .handwriting: "Handwriting"
        case .typed: "Typed text"
        case .pdf: "PDF text"
        case .title: "Title"
        }
    }

    private var accessibilityLabel: String {
        let place = showsNotebookTitle
            ? String(localized: "\(result.notebookTitle), page \(result.pageNumber)", table: "Search")
            : String(localized: "Page \(result.pageNumber)", table: "Search")
        return "\(place). \(result.hit.snippet.text)"
    }
}

/// Page thumbnail with translucent highlights where the search words are.
struct HighlightedThumbnail: View {
    let result: PageResult
    let services: AppServices
    let highlighter: HitHighlighter

    @State private var image: CGImage?
    @State private var rects: [CGRect] = []

    var body: some View {
        let size = services.pages.page(id: result.pageID)?.size ?? CGSize(width: 595, height: 842)
        ZStack {
            Rectangle().fill(Theme.paper)
            if let image { Image(decorative: image, scale: 2).resizable().scaledToFit() }
        }
        .aspectRatio(size.width / max(size.height, 1), contentMode: .fit)
        .overlay { highlights }
        .shadow(color: Theme.shadowColor, radius: 4, y: 2)
        .task(id: result.pageID) {
            image = await services.pageRenderer.thumbnail(pageID: result.pageID, width: 240)
            rects = await highlighter.rects(for: result.hit)
        }
    }

    private var highlights: some View {
        GeometryReader { proxy in
            ForEach(Array(rects.enumerated()), id: \.offset) { _, r in
                Rectangle()
                    .fill(Theme.sunflower.opacity(0.4))
                    .blendMode(.multiply)
                    .frame(width: r.width * proxy.size.width, height: r.height * proxy.size.height)
                    .offset(x: r.minX * proxy.size.width, y: r.minY * proxy.size.height)
            }
        }
        .allowsHitTesting(false)
    }
}

extension View {
    /// Result rows in the search lists: no separator or row background, cards float on the paper.
    func searchCardRow(padded: Bool = true) -> some View {
        Group {
            if padded { padding(12).paperCard() } else { self }
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
    }
}
