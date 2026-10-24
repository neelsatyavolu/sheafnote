import Foundation
import Observation
import OSLog
import SheafnoteCore

/// Editing state for one text document. Edits are applied to a value-type `RichTextDocument`, saved to
/// `Notebook.richText` shortly after the last change (and when the editor closes), with a simple undo history.
@MainActor @Observable
final class TextDocumentModel {
    private static let log = Logger(subsystem: "co.xanom.sheafnote", category: "textdoc")
    private static let saveDelay: Duration = .milliseconds(600)
    private static let typingUndoInterval: TimeInterval = 1.0
    private static let historyLimit = 100

    let notebook: Notebook
    let services: AppServices

    private(set) var document: RichTextDocument = .empty
    /// Set when the stored text couldn't be read. The editor is read-only and never saves, so the stored data is kept.
    private(set) var loadError: String?
    var saveError: String?
    var focusedBlock: UUID?

    private var undoStack: [RichTextDocument] = []
    private var redoStack: [RichTextDocument] = []
    private var lastUndoPush = Date.distantPast
    private var hasUnsavedChanges = false
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    /// The stored text this editor last loaded or wrote; a different stored value means sync changed it meanwhile.
    @ObservationIgnored private var knownStored: Data?
    @ObservationIgnored private var syncObserver: (any NSObjectProtocol)?

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    var isEditable: Bool { loadError == nil }

    init(notebook: Notebook, services: AppServices) {
        self.notebook = notebook
        self.services = services
        load()
        syncObserver = NotificationCenter.default.addObserver(forName: .sheafnoteServerChangesApplied, object: nil,
                                                              queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.storeDidChange() }
        }
    }

    isolated deinit {
        if let syncObserver { NotificationCenter.default.removeObserver(syncObserver) }
    }

    /// iCloud wrote a newer text into the store. With nothing unsaved here, show it; otherwise the next save keeps the
    /// stored version as a copy before writing ours (see `flush`).
    private func storeDidChange() {
        guard !hasUnsavedChanges, notebook.richText != knownStored else { return }
        undoStack.removeAll()
        redoStack.removeAll()
        document = .empty
        loadError = nil
        load()
    }

    private func load() {
        knownStored = notebook.richText
        guard let data = notebook.richText, !data.isEmpty else { return }
        do {
            document = try RichTextDocument.decode(data)
        } catch {
            Self.log.error("Text document unreadable: \(error.localizedDescription, privacy: .public)")
            loadError = error.localizedDescription
        }
    }

    // MARK: Editing

    /// Typing in a block. Newlines split blocks.
    func edit(text: String, in id: UUID) {
        guard isEditable else { return }
        let result = document.applyingEdit(text, to: id)
        guard result.document != document else { return }
        let structural = result.document.blocks.count != document.blocks.count
        apply(result.document, coalescing: !structural)
        if structural { focusedBlock = result.focus }
    }

    func change(_ transform: (RichTextDocument) -> RichTextDocument) {
        guard isEditable else { return }
        apply(transform(document), coalescing: false)
    }

    func insertImage(data: Data) throws {
        guard isEditable else { return }
        let asset: Asset
        do {
            asset = try services.pages.importAsset(data: data, kind: .image, filename: nil)
        } catch {
            throw DocTypesError.saveFailed(error.localizedDescription)
        }
        let result = document.insertingImage(asset.id, after: focusedBlock ?? document.blocks.last?.id)
        apply(result.document, coalescing: false)
        focusedBlock = result.focus
    }

    private func apply(_ new: RichTextDocument, coalescing: Bool) {
        let now = Date.now
        if !coalescing || now.timeIntervalSince(lastUndoPush) > Self.typingUndoInterval {
            undoStack.append(document)
            if undoStack.count > Self.historyLimit { undoStack.removeFirst() }
            lastUndoPush = now
        }
        redoStack.removeAll()
        document = new
        scheduleSave()
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(document)
        document = previous
        lastUndoPush = .distantPast
        scheduleSave()
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(document)
        document = next
        lastUndoPush = .distantPast
        scheduleSave()
    }

    // MARK: Saving

    private func scheduleSave() {
        hasUnsavedChanges = true
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: Self.saveDelay)
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }

    /// Writes pending changes now. Called when the editor closes or the app leaves the foreground.
    func flush() {
        saveTask?.cancel()
        guard hasUnsavedChanges, isEditable else { return }
        // Sync replaced the stored text since we loaded it: keep that version as a copy instead of overwriting it.
        if let stored = notebook.richText, !stored.isEmpty, stored != knownStored {
            TextConflictCopy.keep(stored, from: notebook, in: services.context)
        }
        let encoded = document.encoded()
        notebook.richText = encoded
        markDirty(notebook, fields: ["richText"])
        do {
            try services.context.save()
            knownStored = encoded
            hasUnsavedChanges = false
        } catch {
            Self.log.error("Saving text document failed: \(error.localizedDescription, privacy: .public)")
            saveError = DocTypesError.saveFailed(error.localizedDescription).errorDescription
        }
    }
}
