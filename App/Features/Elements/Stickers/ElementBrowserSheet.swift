import SwiftUI
import SheafnoteCore

@MainActor
enum ElementBrowserPresenter {
    static func present(editor: EditorContext, host: FeatureHost) {
        let inserter = ElementInserter(editor: editor, host: host)
        editor.present(EditorSheet(detents: [.medium, .large]) {
            AnyView(ElementBrowserSheet(editor: editor, inserter: inserter))
        })
    }
}

/// Sheet with the built-in stickers and the user's saved elements.
struct ElementBrowserSheet: View {
    enum Tab: Hashable { case stickers, saved }

    let editor: EditorContext
    let inserter: ElementInserter

    @Environment(\.dismiss) private var dismiss
    @State private var tab: Tab = .stickers

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker(selection: $tab) {
                    Text("Stickers", tableName: "Elements").tag(Tab.stickers)
                    Text("Saved", tableName: "Elements").tag(Tab.saved)
                } label: { Text("Source", tableName: "Elements") }
                .pickerStyle(.segmented)
                .padding([.horizontal, .top])
                .accessibilityIdentifier("elements.browser.tabs")
                switch tab {
                case .stickers: StickerGrid(onPick: insertSticker)
                case .saved: SavedElementsView(editor: editor, onPick: insertSaved)
                }
            }
            .navigationTitle(Text("Elements", tableName: "Elements"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Text("Done", tableName: "Elements") }
                }
            }
        }
    }

    private func insertSticker(_ sticker: StickerDefinition) {
        do {
            try inserter.insertSticker(sticker)
            dismiss()
        } catch {
            ElementErrors.report(error, editor: editor)
        }
    }

    private func insertSaved(_ saved: SavedElementValue) {
        do {
            try inserter.insertSaved(saved)
            dismiss()
        } catch {
            ElementErrors.report(error, editor: editor)
        }
    }
}

struct StickerGrid: View {
    let onPick: (StickerDefinition) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20, pinnedViews: []) {
                ForEach(StickerCategory.allCases, id: \.self) { category in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(title(for: category)).font(.headline).accessibilityAddTraits(.isHeader)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: category == .washi ? 150 : 76), spacing: 12)], spacing: 12) {
                            ForEach(StickerCatalog.stickers(in: category)) { sticker in tile(sticker) }
                        }
                    }
                }
            }
            .padding()
        }
    }

    private func tile(_ sticker: StickerDefinition) -> some View {
        Button { onPick(sticker) } label: {
            StickerArtView(sticker: sticker, tintHex: nil)
                .aspectRatio(sticker.aspectRatio, contentMode: .fit)
                .padding(8)
                .frame(maxWidth: .infinity, minHeight: 72)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(String(localized: String.LocalizationValue(sticker.name), table: "Elements")))
        .accessibilityHint(Text("Adds this sticker to the page", tableName: "Elements"))
        .accessibilityIdentifier("elements.sticker.\(sticker.id)")
    }

    private func title(for category: StickerCategory) -> String {
        switch category {
        case .shapes: String(localized: "Shapes", table: "Elements")
        case .arrows: String(localized: "Arrows", table: "Elements")
        case .tabs: String(localized: "Tabs and labels", table: "Elements")
        case .washi: String(localized: "Washi tape", table: "Elements")
        case .marks: String(localized: "Marks", table: "Elements")
        }
    }
}
