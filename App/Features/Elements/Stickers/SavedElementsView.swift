import SwiftUI
import SheafnoteCore

/// The "Saved" tab: browse, rename, delete and insert elements saved with "Save as element".
struct SavedElementsView: View {
    let editor: EditorContext
    let onPick: (SavedElementValue) -> Void

    @State private var items: [SavedElementValue] = []
    @State private var loaded = false
    @State private var renaming: SavedElementValue?
    @State private var newName = ""
    @State private var deleting: SavedElementValue?

    private var library: any ElementLibrary { editor.services.elementLibrary }

    var body: some View {
        Group {
            if items.isEmpty && loaded {
                ContentUnavailableView {
                    Label { Text("No saved elements yet", tableName: "Elements") } icon: { Image(systemName: "square.dashed") }
                } description: {
                    Text("Select ink, text or images and choose Save as element to keep them here.", tableName: "Elements")
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 12)], spacing: 12) {
                        ForEach(items) { item in tile(item) }
                    }
                    .padding()
                }
            }
        }
        .task { reload() }
        .alert(Text("Rename element", tableName: "Elements"), isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField(String(localized: "Name", table: "Elements"), text: $newName)
            Button(role: .cancel) {} label: { Text("Cancel", tableName: "Elements") }
            Button { commitRename() } label: { Text("Rename", tableName: "Elements") }
        }
        .confirmationDialog(Text("Delete this saved element?", tableName: "Elements"), isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible) {
            Button(role: .destructive) { commitDelete() } label: { Text("Delete", tableName: "Elements") }
        } message: {
            Text("Copies already on your pages are not affected.", tableName: "Elements")
        }
    }

    private func tile(_ item: SavedElementValue) -> some View {
        Button { onPick(item) } label: {
            VStack(spacing: 6) {
                thumbnail(item)
                    .frame(height: 88)
                    .frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous).fill(Theme.paperRaised))
                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous).strokeBorder(Theme.rule, lineWidth: 1))
                Text(item.name).font(.footnote).lineLimit(1)
                Text(item.category).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { newName = item.name; renaming = item } label: { Label { Text("Rename", tableName: "Elements") } icon: { Image(systemName: "pencil") } }
            Button(role: .destructive) { deleting = item } label: { Label { Text("Delete", tableName: "Elements") } icon: { Image(systemName: "trash") } }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(item.name))
        .accessibilityValue(Text(item.category))
        .accessibilityHint(Text("Adds this element to the page", tableName: "Elements"))
        .accessibilityAction(named: Text("Rename", tableName: "Elements")) { newName = item.name; renaming = item }
        .accessibilityAction(named: Text("Delete", tableName: "Elements")) { deleting = item }
        .accessibilityIdentifier("elements.saved.\(item.id.uuidString)")
    }

    @ViewBuilder
    private func thumbnail(_ item: SavedElementValue) -> some View {
        if let image = UIImage(data: item.thumbnail) {
            Image(uiImage: image).resizable().scaledToFit().padding(6)
        } else {
            Image(systemName: "square.dashed").foregroundStyle(.secondary)
        }
    }

    private func reload() {
        do {
            items = try library.all()
        } catch {
            ElementErrors.report(error, editor: editor)
        }
        loaded = true
    }

    private func commitRename() {
        guard let item = renaming else { return }
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        renaming = nil
        guard !name.isEmpty else { return }
        do { try library.rename(id: item.id, to: name) } catch { ElementErrors.report(error, editor: editor) }
        reload()
    }

    private func commitDelete() {
        guard let item = deleting else { return }
        deleting = nil
        do { try library.delete(id: item.id) } catch { ElementErrors.report(error, editor: editor) }
        reload()
    }
}
