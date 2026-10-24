import PencilKit
import SwiftUI
import SheafnoteCore

/// A selection action defined by closures, so each built-in action is a few lines.
@MainActor
final class ClosureSelectionAction: SelectionAction {
    let id: String
    let title: LocalizedStringResource
    let symbolName: String
    let order: Int
    private let enabled: @MainActor (SelectionModel, any EditorContext) -> Bool
    private let run: @MainActor (SelectionModel, any PageContext, any EditorContext) async throws -> Void

    init(id: String, title: LocalizedStringResource, symbolName: String, order: Int,
         enabled: @escaping @MainActor (SelectionModel, any EditorContext) -> Bool = { selection, _ in !selection.isEmpty },
         run: @escaping @MainActor (SelectionModel, any PageContext, any EditorContext) async throws -> Void) {
        self.id = id; self.title = title; self.symbolName = symbolName; self.order = order
        self.enabled = enabled; self.run = run
    }

    func isEnabled(for selection: SelectionModel, editor: EditorContext) -> Bool { enabled(selection, editor) }

    func perform(selection: SelectionModel, page: any PageContext, editor: EditorContext) async throws {
        try await run(selection, page, editor)
    }
}

/// The lasso's selection actions: copy, cut, duplicate, delete, style, screenshot, convert to text, save as element.
@MainActor
enum InkSelectionActions {
    static func make(host: FeatureHost, clipboard: ClipboardService) -> [any SelectionAction] {
        [copy(clipboard), cut(clipboard), duplicate(), delete(), style(), screenshot(host), convert(host), saveElement(host)]
    }

    private static func contents(_ selection: SelectionModel, _ page: any PageContext) throws -> SelectionContents {
        guard let contents = SelectionContents(selection: selection, page: page) else { throw InkToolsError.pageNotReady }
        return contents
    }

    // MARK: Clipboard and structure

    private static func copy(_ clipboard: ClipboardService) -> ClosureSelectionAction {
        ClosureSelectionAction(id: "ink.copy", title: LocalizedStringResource("Copy", table: "InkTools"), symbolName: "doc.on.doc", order: 10) {
            selection, page, editor in
            await clipboard.copy(try contents(selection, page), page: page)
            editor.showToast(LocalizedStringResource("Copied", table: "InkTools"))
        }
    }

    /// Copies first; the selection is removed only once the copy is on the pasteboard.
    private static func cut(_ clipboard: ClipboardService) -> ClosureSelectionAction {
        ClosureSelectionAction(id: "ink.cut", title: LocalizedStringResource("Cut", table: "InkTools"), symbolName: "scissors", order: 20) {
            selection, page, editor in
            await clipboard.copy(try contents(selection, page), page: page)
            try editor.selectionTransformer.delete(selection: selection, in: page)
            editor.showToast(LocalizedStringResource("Cut", table: "InkTools"))
        }
    }

    private static func duplicate() -> ClosureSelectionAction {
        ClosureSelectionAction(id: "ink.duplicate", title: LocalizedStringResource("Duplicate", table: "InkTools"),
                               symbolName: "plus.square.on.square", order: 30) { selection, page, editor in
            let snapshot = try editor.selectionTransformer.duplicate(selection: selection, in: page, offset: .zero)
            let strokeIDs = snapshot.strokes.isEmpty ? [] : Set(try PKDrawing(data: snapshot.strokes).strokeIDs)
            selection.select(pageID: page.pageID, strokeIDs: strokeIDs, elementIDs: Set(snapshot.elements.map(\.id)), bounds: snapshot.bounds)
        }
    }

    private static func delete() -> ClosureSelectionAction {
        ClosureSelectionAction(id: "ink.delete", title: LocalizedStringResource("Delete", table: "InkTools"), symbolName: "trash", order: 40) {
            selection, page, editor in
            try editor.selectionTransformer.delete(selection: selection, in: page)
        }
    }

    // MARK: Style

    private static func style() -> ClosureSelectionAction {
        ClosureSelectionAction(
            id: "ink.style", title: LocalizedStringResource("Style", table: "InkTools"), symbolName: "paintpalette", order: 50,
            enabled: { selection, editor in
                let page = editor.visiblePages.first(where: { $0.pageID == selection.pageID }) ?? editor.currentPage
                guard let page else { return !selection.strokeIDs.isEmpty }
                return SelectionContents(selection: selection, page: page)?.isStyleable ?? false
            }
        ) { selection, page, editor in
            let styler = SelectionStyler(selection: selection, page: page, editor: editor)
            editor.present(EditorSheet(detents: [.medium, .large]) { AnyView(SelectionStyleSheet(styler: styler)) })
        }
    }

    // MARK: Screenshot, text, element

    private static func screenshot(_ host: FeatureHost) -> ClosureSelectionAction {
        ClosureSelectionAction(id: "ink.screenshot", title: LocalizedStringResource("Screenshot", table: "InkTools"),
                               symbolName: "camera.viewfinder", order: 60) { selection, page, editor in
            let image = try await SelectionImageRenderer(host: host).image(of: contents(selection, page), scale: 3)
            editor.present(EditorSheet(detents: [.medium, .large]) { AnyView(SelectionScreenshotSheet(image: image)) })
        }
    }

    private static func convert(_ host: FeatureHost) -> ClosureSelectionAction {
        ClosureSelectionAction(
            id: "ink.convertText", title: LocalizedStringResource("Convert to Text", table: "InkTools"), symbolName: "textformat", order: 70,
            enabled: { selection, _ in !selection.strokeIDs.isEmpty }
        ) { selection, page, editor in
            let conversion = TextConversion(host: host)
            let source = try contents(selection, page)
            guard !source.strokes.isEmpty else { return }
            let text = try await conversion.recognizedText(for: source)
            editor.present(EditorSheet(detents: [.medium, .large]) {
                AnyView(ConvertTextSheet(text: text, canReplace: page is PageSession,
                                         insert: { text in run(editor) { try conversion.place(text, over: source, page: page, editor: editor, replacing: false) } },
                                         replace: { text in run(editor) { try conversion.place(text, over: source, page: page, editor: editor, replacing: true) } }))
            })
        }
    }

    private static func saveElement(_ host: FeatureHost) -> ClosureSelectionAction {
        ClosureSelectionAction(id: "ink.saveElement", title: LocalizedStringResource("Save as Element", table: "InkTools"),
                               symbolName: "star.square.on.square", order: 80) { selection, page, editor in
            let source = try contents(selection, page)
            let thumbnail = try await SelectionImageRenderer(host: host).image(of: source, scale: 1).pngData() ?? Data()
            let proposed = String(localized: "My Element", table: "InkTools")
            editor.present(EditorSheet(detents: [.height(220)]) {
                AnyView(SaveElementSheet(name: proposed) { name in
                    run(editor) {
                        try editor.services.elementLibrary.save(name: name, category: String(localized: "My Elements", table: "InkTools"),
                                                                from: source.snapshot, thumbnail: thumbnail)
                        editor.showToast(LocalizedStringResource("Saved to your elements", table: "InkTools"))
                    }
                })
            })
        }
    }

    /// Runs an edit from a sheet button; a failure is shown to the user, never dropped.
    private static func run(_ editor: EditorContext, _ body: () throws -> Void) {
        do { try body() } catch { InkToolsErrors.report(error, editor: editor) }
    }
}
