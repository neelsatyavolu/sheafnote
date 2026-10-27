import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import SheafnoteCore

/// "Photos" and "Files" buttons that set `photo` to the picked picture, cropped to a cover by `CoverPhoto`.
struct CoverPhotoButtons: View {
    @Binding var photo: Data?
    /// Prefix for the buttons' accessibility identifiers (`<prefix>.photos`, `<prefix>.files`).
    let identifier: String

    @State private var photoItem: PhotosPickerItem?
    @State private var showFiles = false
    @State private var failed = false

    var body: some View {
        HStack(spacing: 20) {
            PhotosPicker(selection: $photoItem, matching: .images) {
                Label("Photos", systemImage: "photo")
            }
            .accessibilityIdentifier("\(identifier).photos")
            Button { showFiles = true } label: {
                Label("Files", systemImage: "folder")
            }
            .accessibilityIdentifier("\(identifier).files")
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { await loadPhoto(item) }
        }
        .fileImporter(isPresented: $showFiles, allowedContentTypes: [.image]) { result in
            Task { await importFile(result) }
        }
        .alert("Couldn't use that photo", isPresented: $failed) { Button("OK", role: .cancel) {} }
    }

    private func loadPhoto(_ item: PhotosPickerItem) async {
        defer { photoItem = nil }
        await use(try? await item.loadTransferable(type: Data.self))
    }

    private func importFile(_ result: Result<URL, Error>) async {
        guard let url = try? result.get() else {
            failed = true
            return
        }
        // Read off the main actor too: a file provider may have to download it first.
        let data = await Task.detached {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            return try? Data(contentsOf: url)
        }.value
        await use(data)
    }

    /// Crops off the main actor; a full-size photo takes a moment to decode.
    private func use(_ data: Data?) async {
        guard let data, let cover = await Task.detached(operation: { CoverPhoto.jpeg(from: data) }).value else {
            failed = true
            return
        }
        photo = cover
    }
}
