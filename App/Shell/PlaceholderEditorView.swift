import SwiftUI
import SheafnoteCore

/// Shown when no editor is registered for a notebook kind. The editor unit registers a real factory instead.
struct PlaceholderEditorView: View {
    let notebook: Notebook
    let services: AppServices
    @Environment(\.dismiss) private var dismiss
    @State private var thumbnail: CGImage?

    private var pageCount: Int { (try? services.pages.orderedPages(of: notebook.id).count) ?? 0 }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if let thumbnail {
                    Image(decorative: thumbnail, scale: 1)
                        .resizable().scaledToFit().frame(maxHeight: 360)
                        .border(.separator).shadow(radius: 6, y: 2)
                        .accessibilityHidden(true)
                }
                Text(notebook.title).font(.title2.bold()).accessibilityIdentifier("placeholderEditor.title")
                Text("\(pageCount) pages")
                    .foregroundStyle(.secondary).accessibilityIdentifier("placeholderEditor.pageCount")
                Text("The page editor is not available in this build yet.")
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle(notebook.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Library", systemImage: "chevron.backward") { dismiss() }
                        .accessibilityLabel(Text("Back to library"))
                        .accessibilityIdentifier("placeholderEditor.close")
                }
            }
        }
        .accessibilityIdentifier("placeholderEditor")
        .task {
            guard let first = try? services.pages.orderedPages(of: notebook.id).first else { return }
            thumbnail = await services.pageRenderer.thumbnail(pageID: first.id, width: 600)
        }
    }
}
