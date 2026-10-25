import PhotosUI
import SwiftUI
import SheafnoteCore

struct ChangeCoverSheet: View {
    let notebookID: UUID

    @Environment(LibrarySession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var selected: String
    /// The picked photo (already downscaled). Choosing a built-in cover clears it.
    @State private var photo: Data?
    @State private var photoItem: PhotosPickerItem?
    @State private var photoFailed = false
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
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label("Choose Photo", systemImage: "photo")
                    }
                    .accessibilityIdentifier("changeCover.photo")
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
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task { await loadPhoto(item) }
            }
            .alert("Couldn't use that photo", isPresented: $photoFailed) { Button("OK", role: .cancel) {} }
        }
        .presentationDetents([.medium, .large])
    }

    private func loadPhoto(_ item: PhotosPickerItem) async {
        defer { photoItem = nil }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data), let cover = Self.coverJPEG(from: image) else {
            photoFailed = true
            return
        }
        photo = cover
    }

    /// Crops the photo to the 3:4 cover shape at 600×800 so the notebook record stays small enough to sync.
    static func coverJPEG(from image: UIImage) -> Data? {
        let target = CGSize(width: 600, height: 800)
        guard image.size.width > 0, image.size.height > 0 else { return nil }
        let scale = max(target.width / image.size.width, target.height / image.size.height)
        let drawn = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let rendered = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(x: (target.width - drawn.width) / 2, y: (target.height - drawn.height) / 2,
                                  width: drawn.width, height: drawn.height))
        }
        return rendered.jpegData(compressionQuality: 0.75)
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
