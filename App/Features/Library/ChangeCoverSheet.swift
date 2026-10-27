import SwiftUI
import SheafnoteCore

struct ChangeCoverSheet: View {
    let notebookID: UUID

    @Environment(LibrarySession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var selected: String
    /// The picked photo (already downscaled). Choosing a built-in cover clears it.
    @State private var photo: Data?
    @ScaledMetric private var cellWidth: CGFloat = 100

    private var previewTitle: String? { session.services.library.notebook(id: notebookID)?.title }

    init(notebookID: UUID) {
        self.notebookID = notebookID
        _selected = State(initialValue: "")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    CoverPhotoButtons(photo: $photo, identifier: "changeCover.photo")
                    if let photo {
                        NotebookCoverView(cover: CoverSpec(coverID: selected, image: photo), title: previewTitle)
                            .frame(maxWidth: 140)
                            .accessibilityIdentifier("changeCover.photoPreview")
                    }
                    CoverGrid(selectedID: Binding(get: { photo == nil ? selected : "" },
                                                  set: { selected = $0; photo = nil }),
                              cellWidth: cellWidth, previewTitle: previewTitle)
                }
                .padding()
            }
            .background(Theme.paper)
            .navigationTitle("Change Cover")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        LibraryActions(session: session).setCover(notebookID, CoverSpec(coverID: selected, image: photo))
                        dismiss()
                    }
                    .disabled(selected.isEmpty).accessibilityIdentifier("changeCover.done")
                }
            }
            .onAppear {
                if selected.isEmpty, let nb = session.services.library.notebook(id: notebookID) {
                    selected = nb.cover.coverID
                    photo = nb.cover.image
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Grid of every built-in cover with a selection ring.
struct CoverGrid: View {
    @Binding var selectedID: String
    let cellWidth: CGFloat
    var previewTitle: String?

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: cellWidth), spacing: 16)], spacing: 16) {
            ForEach(CoverCatalog.all) { cover in
                Button { selectedID = cover.id } label: { CoverChoice(definition: cover, title: previewTitle, isSelected: selectedID == cover.id) }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(cover.title))
                    .accessibilityAddTraits(selectedID == cover.id ? [.isButton, .isSelected] : .isButton)
                    .accessibilityIdentifier("cover.\(cover.id)")
            }
        }
    }
}

struct CoverChoice: View {
    let definition: CoverDefinition
    var title: String?
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 6) {
            NotebookCoverView(cover: CoverSpec(coverID: definition.id), title: title)
                .padding(4)
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                    .stroke(Theme.accent, lineWidth: isSelected ? 3 : 0))
            Text(definition.title).font(.caption).foregroundStyle(isSelected ? Theme.accent : Theme.inkMuted)
        }
    }
}
