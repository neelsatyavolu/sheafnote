import PencilKit
import UIKit
import SheafnoteCore

/// Handwriting to text: read the selected ink with Vision, let the user check the result, then add a text element
/// (keeping the ink) or replace the ink with it (after saving a copy of the page).
@MainActor
struct TextConversion {
    let host: FeatureHost

    func recognizedText(for contents: SelectionContents) async throws -> String {
        let image = try await SelectionImageRenderer(host: host).handwritingImage(of: contents)
        let result = try await host.services.recognizer.recognizeText(in: image, languages: [])
        let text = result.fullText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw InkToolsError.noTextFound }
        return text
    }

    /// Adds the text box over the handwriting. With `replacing`, the handwriting is removed in the same undo step.
    func place(_ text: String, over contents: SelectionContents, page: any PageContext, editor: EditorContext,
               replacing: Bool) throws {
        let manager = editor.undoManager
        manager.beginUndoGrouping()
        defer { manager.endUndoGrouping() }
        if replacing { try saveCopyOfPage(page) }
        let layout = HandwritingTextLayout.layout(text: text, over: contents.bounds, pageSize: page.pageSize)
        let payload = TextPayload(text: text, fontSize: layout.fontSize, colorHex: inkColorHex(of: contents))
        let top = page.elements.all.map(\.zIndex).max() ?? 0
        let element = ElementValue(pageID: page.pageID, kind: .text, frame: layout.frame, zIndex: top + 1,
                                   payload: PayloadCodec.encode(payload))
        let stored = try page.elements.add(element, undoName: LocalizedStringResource("Convert to Text", table: "InkTools"))
        if replacing {
            let removing = Set(contents.strokes.map(\.id))
            let doomed = Set(page.ink.strokes.enumerated().filter { removing.contains($0.element.id) }.map(\.offset))
            page.ink.edit(LocalizedStringResource("Replace Handwriting", table: "InkTools")) { strokes in
                strokes = strokes.enumerated().filter { !doomed.contains($0.offset) }.map(\.element)
            }
        }
        editor.selection.select(pageID: page.pageID, strokeIDs: [], elementIDs: [stored.id], bounds: layout.frame)
    }

    /// Replacing removes ink, so the page goes to the Recovered area first (with what is on screen, not what was last saved).
    private func saveCopyOfPage(_ page: any PageContext) throws {
        guard let live = page as? PageSession else { throw InkToolsError.pageNotReady }
        live.flush()
        guard let stored = host.services.pages.page(id: page.pageID) else { throw InkToolsError.pageNotReady }
        try host.services.revisions.snapshot(page: stored, reason: .beforeClear, note: "Convert handwriting to text")
    }

    private func inkColorHex(of contents: SelectionContents) -> String {
        contents.strokes.first?.stroke.ink.color.hexString ?? "#000000"
    }
}
