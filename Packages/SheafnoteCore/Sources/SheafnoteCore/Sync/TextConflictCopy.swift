import Foundation
import SwiftData

/// A text document is one blob, so two devices editing it at once cannot be merged field by field. Instead of letting
/// one side's text vanish, the losing version is kept as a second document next to the first.
@MainActor
public enum TextConflictCopy {
    public static let titleSuffix = " (iCloud copy)"

    /// Stores `text` as a new text document beside `notebook` (same folder, same look). Not saved: the caller saves.
    @discardableResult
    public static func keep(_ text: Data, from notebook: Notebook, in context: ModelContext, now: Date = .now) -> Notebook {
        let copy = Notebook(title: notebook.title + titleSuffix, kind: notebook.kind, folderID: notebook.folderID,
                            cover: notebook.cover, template: notebook.template, paperSize: notebook.paperSizeValue,
                            orientation: notebook.orientationValue, paperColor: notebook.paperColorValue,
                            sortKey: SortKey.between(notebook.sortKey, nil), now: now)
        copy.richText = text
        context.insert(copy)
        markDirty(copy, fields: LibraryStore.notebookFields, now: now)
        return copy
    }

    /// Sync found a server text that differs from our unsent one: ours stays, the server's goes to a copy.
    static func preserveServerText(for notebook: Notebook, server r: SyncRecord, in context: ModelContext, now: Date) {
        guard notebook.kind == .text, notebook.dirtyFields.contains("richText"),
              let theirs = r.bytes("richText"), !theirs.isEmpty, theirs != notebook.richText else { return }
        keep(theirs, from: notebook, in: context, now: now)
    }
}
