import PencilKit
import SwiftUI
import UIKit
import SheafnoteCore

/// "Save as element": stores the selected ink and elements in the saved-elements library.
@MainActor
final class SaveAsElementAction: SelectionAction {
    let id = "elements.save"
    let title = LocalizedStringResource("Save as Element", table: "Elements")
    let symbolName = "square.and.arrow.down.on.square"
    let order = 80

    static let defaultCategory = "My Elements"
    private static let thumbnailWidth: CGFloat = 240

    func isEnabled(for selection: SelectionModel, editor: EditorContext) -> Bool {
        !selection.isEmpty && selection.bounds != nil
    }

    func perform(selection: SelectionModel, page: any PageContext, editor: EditorContext) async throws {
        guard let bounds = selection.bounds, !selection.isEmpty else { return }
        let snapshot = makeSnapshot(selection: selection, page: page, bounds: bounds)
        let pageID = page.pageID
        editor.present(EditorSheet(detents: [.medium]) {
            AnyView(SaveElementSheet(initialName: String(localized: "Untitled element", table: "Elements"),
                                     category: Self.defaultCategory) { name, category in
                await Self.save(name: name, category: category, snapshot: snapshot, pageID: pageID, editor: editor)
            })
        })
    }

    func makeSnapshot(selection: SelectionModel, page: any PageContext, bounds: CGRect) -> SelectionSnapshot {
        let strokes = page.ink.strokes.filter { selection.strokeIDs.contains($0.id) }.map(\.stroke)
        let elements = page.elements.all.filter { selection.elementIDs.contains($0.id) }
        return SelectionSnapshot(strokes: PKDrawing(strokes: strokes).dataRepresentation(), elements: elements, bounds: bounds)
    }

    /// Returns true when saved, so the sheet can close; a failure is shown and the sheet stays open for another try.
    private static func save(name: String, category: String, snapshot: SelectionSnapshot, pageID: UUID, editor: EditorContext) async -> Bool {
        do {
            let thumbnail = try await thumbnailData(for: snapshot, pageID: pageID, editor: editor)
            try editor.services.elementLibrary.save(name: name, category: category, from: snapshot, thumbnail: thumbnail)
            editor.showToast(LocalizedStringResource("Saved to your elements", table: "Elements"))
            return true
        } catch {
            ElementErrors.report(error, editor: editor)
            return false
        }
    }

    private static func thumbnailData(for snapshot: SelectionSnapshot, pageID: UUID, editor: EditorContext) async throws -> Data {
        let options = RenderOptions(includeBackground: false, includeInk: true, includeElements: true, forExport: false, hideTape: false)
        let scale = min(thumbnailWidth / max(snapshot.bounds.width, 1), 2)
        let image = try await editor.services.pageRenderer.renderImage(pageID: pageID, rect: snapshot.bounds, scale: scale, options: options)
        guard let data = UIImage(cgImage: image).pngData() else { throw ImageImportError.encodeFailed }
        return data
    }
}

/// "Edit text" for a single selected text box.
@MainActor
final class EditTextAction: SelectionAction {
    let id = "elements.editText"
    let title = LocalizedStringResource("Edit Text", table: "Elements")
    let symbolName = "pencil"
    let order = 20
    private unowned let host: FeatureHost

    init(host: FeatureHost) { self.host = host }

    func isEnabled(for selection: SelectionModel, editor: EditorContext) -> Bool {
        guard let page = editor.currentPage else { return false }
        return ElementSelecting.selectedElement(on: page, editor: editor)?.kind == .text
    }

    func perform(selection: SelectionModel, page: any PageContext, editor: EditorContext) async throws {
        guard let element = ElementSelecting.selectedElement(on: page, editor: editor), element.kind == .text else { return }
        host.elementRenderers.renderer(for: .text)?.beginEditing(element, page: page, editor: editor)
    }
}

/// "Crop" for a single selected image.
@MainActor
final class CropImageAction: SelectionAction {
    let id = "elements.crop"
    let title = LocalizedStringResource("Crop Image", table: "Elements")
    let symbolName = "crop"
    let order = 21
    private unowned let host: FeatureHost

    init(host: FeatureHost) { self.host = host }

    func isEnabled(for selection: SelectionModel, editor: EditorContext) -> Bool {
        guard let page = editor.currentPage else { return false }
        return ElementSelecting.selectedElement(on: page, editor: editor)?.kind == .image
    }

    func perform(selection: SelectionModel, page: any PageContext, editor: EditorContext) async throws {
        guard let element = ElementSelecting.selectedElement(on: page, editor: editor), element.kind == .image else { return }
        host.elementRenderers.renderer(for: .image)?.beginEditing(element, page: page, editor: editor)
    }
}

/// Asks for a name and category, then saves. `onSave` returns true when the element was saved.
struct SaveElementSheet: View {
    let initialName: String
    let category: String
    let onSave: (String, String) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var categoryText = ""
    @State private var saving = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(String(localized: "Name", table: "Elements"), text: $name)
                        .accessibilityIdentifier("elements.save.name")
                    TextField(String(localized: "Category", table: "Elements"), text: $categoryText)
                } footer: {
                    Text("Saved elements are kept on this device and synced with iCloud.", tableName: "Elements")
                }
            }
            .navigationTitle(Text("Save as Element", tableName: "Elements"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button { dismiss() } label: { Text("Cancel", tableName: "Elements") } }
                ToolbarItem(placement: .confirmationAction) {
                    Button { save() } label: { Text("Save", tableName: "Elements") }
                        .disabled(trimmedName.isEmpty || saving)
                        .accessibilityIdentifier("elements.save.confirm")
                }
            }
        }
        .onAppear {
            name = initialName
            categoryText = category
        }
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func save() {
        saving = true
        let trimmedCategory = categoryText.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            let saved = await onSave(trimmedName, trimmedCategory.isEmpty ? SaveAsElementAction.defaultCategory : trimmedCategory)
            saving = false
            if saved { dismiss() }
        }
    }
}
