import SwiftUI
import UIKit

/// The picture of a selection, with Share (which includes Save Image), Copy, and Save to Photos.
struct SelectionScreenshotSheet: View {
    let image: UIImage
    @State private var saver = PhotoSaver()
    @State private var status: LocalizedStringKey?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(uiImage: image)
                    .resizable().scaledToFit()
                    .padding(8)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityLabel(Text("Picture of the selection", tableName: "InkTools"))
                HStack(spacing: 12) {
                    ShareLink(item: Image(uiImage: image), preview: SharePreview(Text("Selection", tableName: "InkTools"), image: Image(uiImage: image))) {
                        Label { Text("Share", tableName: "InkTools") } icon: { Image(systemName: "square.and.arrow.up") }
                    }
                    .accessibilityIdentifier("inktools.screenshot.share")
                    Button {
                        UIPasteboard.general.image = image
                        status = "Copied"
                    } label: { Label { Text("Copy", tableName: "InkTools") } icon: { Image(systemName: "doc.on.doc") } }
                        .accessibilityIdentifier("inktools.screenshot.copy")
                    Button { saver.save(image) { status = $0 } } label: {
                        Label { Text("Save to Photos", tableName: "InkTools") } icon: { Image(systemName: "photo.badge.plus") }
                    }
                    .accessibilityIdentifier("inktools.screenshot.save")
                }
                .buttonStyle(.bordered)
                if let status { Text(status, tableName: "InkTools").font(.footnote).foregroundStyle(.secondary).accessibilityAddTraits(.updatesFrequently) }
            }
            .padding()
            .navigationTitle(Text("Selection Screenshot", tableName: "InkTools"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button { dismiss() } label: { Text("Done", tableName: "InkTools") } }
            }
        }
    }
}

/// `UIImageWriteToSavedPhotosAlbum` reports through an Objective-C selector, so this is a small NSObject.
@MainActor
final class PhotoSaver: NSObject {
    private var completion: ((LocalizedStringKey) -> Void)?

    func save(_ image: UIImage, completion: @escaping (LocalizedStringKey) -> Void) {
        self.completion = completion
        UIImageWriteToSavedPhotosAlbum(image, self, #selector(finished(_:error:context:)), nil)
    }

    @objc private func finished(_ image: UIImage, error: NSError?, context: UnsafeRawPointer?) {
        if let error {
            completion?("Could not save to Photos: \(error.localizedDescription)")
        } else {
            completion?("Saved to Photos")
        }
        completion = nil
    }
}
