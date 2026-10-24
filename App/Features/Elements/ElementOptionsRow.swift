import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import SheafnoteCore

/// Options row of the element tool: where to get a picture or sticker from, plus controls for the selected element.
struct ElementOptionsRow: View {
    let editor: EditorContext
    let host: FeatureHost
    let imageCache: ElementImageCache

    @State private var photoItem: PhotosPickerItem?
    @State private var showFiles = false
    @State private var showCamera = false

    private var inserter: ElementInserter { ElementInserter(editor: editor, host: host) }

    var body: some View {
        HStack(spacing: 14) {
            PhotosPicker(selection: $photoItem, matching: .images) {
                Label { Text("Photos", tableName: "Elements") } icon: { Image(systemName: "photo") }
            }
            .accessibilityIdentifier("elements.insert.photos")
            Button { showFiles = true } label: {
                Label { Text("Files", tableName: "Elements") } icon: { Image(systemName: "folder") }
            }
            .accessibilityIdentifier("elements.insert.files")
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button { showCamera = true } label: {
                    Label { Text("Camera", tableName: "Elements") } icon: { Image(systemName: "camera") }
                }
                .accessibilityIdentifier("elements.insert.camera")
            }
            Button { ElementBrowserPresenter.present(editor: editor, host: host) } label: {
                Label { Text("Stickers & Saved", tableName: "Elements") } icon: { Image(systemName: "sparkles") }
            }
            .accessibilityIdentifier("elements.insert.browser")
            SelectedElementControls(editor: editor, host: host, imageCache: imageCache)
        }
        .padding(.horizontal, 12)
        .optionsCapsule()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("elements.options")
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { await loadPhoto(item) }
        }
        .fileImporter(isPresented: $showFiles, allowedContentTypes: [.image], allowsMultipleSelection: false) { result in
            importFile(result)
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { data in
                showCamera = false
                if let data { insert(data, filename: nil) }
            }
            .ignoresSafeArea()
        }
    }

    // MARK: Sources

    private func loadPhoto(_ item: PhotosPickerItem) async {
        defer { photoItem = nil }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { throw ElementInsertError.photoUnavailable }
            insert(data, filename: nil)
        } catch {
            ElementErrors.report(error, editor: editor)
        }
    }

    private func importFile(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            insert(try Data(contentsOf: url), filename: url.lastPathComponent)
        } catch {
            ElementErrors.report(error, editor: editor)
        }
    }

    private func insert(_ data: Data, filename: String?) {
        do { try inserter.insertImage(data: data, filename: filename) } catch { ElementErrors.report(error, editor: editor) }
    }
}

/// Controls that depend on what is selected: order, text edit, crop, sticker tint.
struct SelectedElementControls: View {
    let editor: EditorContext
    let host: FeatureHost
    let imageCache: ElementImageCache

    private var inserter: ElementInserter { ElementInserter(editor: editor, host: host) }

    var body: some View {
        if let page = editor.currentPage, let element = ElementSelecting.selectedElement(on: page, editor: editor) {
            HStack(spacing: 14) {
                Divider().frame(height: 22)
                specific(element, page: page)
                Button { run { try inserter.moveToFront(element) } } label: { Image(systemName: "square.3.layers.3d.top.filled") }
                    .accessibilityLabel(Text("Bring to front", tableName: "Elements"))
                Button { run { try inserter.moveToBack(element) } } label: { Image(systemName: "square.3.layers.3d.bottom.filled") }
                    .accessibilityLabel(Text("Send to back", tableName: "Elements"))
            }
        }
    }

    @ViewBuilder
    private func specific(_ element: ElementValue, page: any PageContext) -> some View {
        switch element.kind {
        case .text:
            Button { host.elementRenderers.renderer(for: .text)?.beginEditing(element, page: page, editor: editor) } label: {
                Label { Text("Edit text", tableName: "Elements") } icon: { Image(systemName: "pencil") }
            }
        case .image:
            Button { ImageCropPresenter.present(element, page: page, editor: editor, cache: imageCache, host: host) } label: {
                Label { Text("Crop", tableName: "Elements") } icon: { Image(systemName: "crop") }
            }
            .accessibilityIdentifier("elements.image.crop")
        case .sticker:
            stickerTint(element, page: page)
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private func stickerTint(_ element: ElementValue, page: any PageContext) -> some View {
        if let payload = element.decoded(StickerPayload.self), let sticker = StickerCatalog.sticker(id: payload.stickerID) {
            let current = payload.tintHex ?? sticker.primaryHex
            ColorPicker(selection: Binding(get: { Color(hex: current) }, set: { setTint($0.hexString, element, page) }),
                        supportsOpacity: false) { Text("Sticker color", tableName: "Elements") }
                .labelsHidden()
            if payload.tintHex != nil {
                Button { setTint(nil, element, page) } label: {
                    Label { Text("Reset color", tableName: "Elements") } icon: { Image(systemName: "arrow.uturn.backward") }
                }
            }
        }
    }

    private func setTint(_ hex: String?, _ element: ElementValue, _ page: any PageContext) {
        guard var payload = element.decoded(StickerPayload.self) else { return }
        payload.tintHex = hex
        let encoded = PayloadCodec.encode(payload)
        run { try page.elements.update(id: element.id, undoName: LocalizedStringResource("Change Sticker Color", table: "Elements")) { $0.payload = encoded } }
    }

    private func run(_ work: () throws -> Void) {
        do { try work() } catch { ElementErrors.report(error, editor: editor) }
    }
}

/// Camera capture as JPEG data. Only offered where a camera exists.
struct CameraPicker: UIViewControllerRepresentable {
    let onFinish: (Data?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onFinish: (Data?) -> Void
        init(onFinish: @escaping (Data?) -> Void) { self.onFinish = onFinish }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            let image = info[.originalImage] as? UIImage
            onFinish(image?.jpegData(compressionQuality: 0.95))
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { onFinish(nil) }
    }
}
