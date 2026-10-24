import PencilKit
import SwiftUI
import UIKit
import SheafnoteCore

/// The lasso's options row: what it picks up (handwriting, images, text), select all, paste, saved elements.
struct LassoOptionsRow: View {
    let settings: InkToolsSettings
    let editor: EditorContext
    let clipboard: ClipboardService
    let tool: LassoTool

    @State private var canPaste = false
    @State private var saved: [SavedElementValue] = []

    var body: some View {
        let filters = settings.lassoFilters
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                filterButton(.handwriting, symbol: "scribble", title: "Handwriting", on: filters)
                filterButton(.images, symbol: "photo", title: "Images", on: filters)
                filterButton(.text, symbol: "textformat", title: "Text", on: filters)
                OptionsDivider()
                Button { selectAll() } label: { Image(systemName: "selection.pin.in.out").frame(minWidth: 44, minHeight: 44) }
                    .accessibilityLabel(Text("Select all on page", tableName: "InkTools"))
                    .accessibilityIdentifier("inktools.lasso.selectAll")
                Button { paste() } label: { Image(systemName: "doc.on.clipboard").frame(minWidth: 44, minHeight: 44) }
                    .disabled(!canPaste)
                    .accessibilityLabel(Text("Paste", tableName: "InkTools"))
                    .accessibilityIdentifier("inktools.lasso.paste")
                savedMenu
            }
            .padding(.horizontal, 12)
        }
        .optionsCapsule()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Lasso options", tableName: "InkTools"))
        .onAppear { refresh() }
        .onReceive(NotificationCenter.default.publisher(for: UIPasteboard.changedNotification)) { _ in refresh() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in refresh() }
    }

    // MARK: Filters

    private func filterButton(_ filter: LassoFilters, symbol: String, title: LocalizedStringKey, on filters: LassoFilters) -> some View {
        let selected = filters.contains(filter)
        return Button { settings.toggleLassoFilter(filter) } label: {
            Image(systemName: symbol)
                .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                .frame(minWidth: 44, minHeight: 44)
                .background { if selected { Circle().fill(Color.accentColor.opacity(0.15)).frame(width: 38, height: 38) } }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title, tableName: "InkTools"))
        .accessibilityValue(selected ? Text("Selected by the lasso", tableName: "InkTools") : Text("Skipped by the lasso", tableName: "InkTools"))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("inktools.lasso.filter.\(symbol)")
    }

    // MARK: Paste and saved elements

    private var savedMenu: some View {
        Menu {
            if saved.isEmpty {
                Text("No saved elements yet", tableName: "InkTools")
            }
            ForEach(saved) { item in
                Button { insert(item) } label: { Text(item.name) }
            }
        } label: {
            Image(systemName: "star.square.on.square").frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityLabel(Text("Insert saved element", tableName: "InkTools"))
        .accessibilityIdentifier("inktools.lasso.saved")
    }

    private func refresh() {
        canPaste = clipboard.canPaste
        do {
            saved = try editor.services.elementLibrary.all()
        } catch {
            saved = []
            InkToolsErrors.report(error, editor: editor)
        }
    }

    private func selectAll() {
        guard let page = editor.currentPage else { return }
        tool.selectAll(page: page, editor: editor)
    }

    private func paste() {
        guard let page = editor.currentPage else { return }
        do { try clipboard.paste(into: page, editor: editor) } catch { InkToolsErrors.report(error, editor: editor) }
    }

    private func insert(_ item: SavedElementValue) {
        guard let page = editor.currentPage else { return }
        do {
            let center = CGPoint(x: page.pageSize.width / 2, y: page.pageSize.height / 2)
            let snapshot = try editor.services.elementLibrary.insert(item, into: page, at: center, scale: 1)
            let strokeIDs = snapshot.strokes.isEmpty ? [] : Set(try PKDrawing(data: snapshot.strokes).strokeIDs)
            editor.selection.select(pageID: page.pageID, strokeIDs: strokeIDs, elementIDs: Set(snapshot.elements.map(\.id)), bounds: snapshot.bounds)
        } catch {
            InkToolsErrors.report(error, editor: editor)
        }
    }
}
