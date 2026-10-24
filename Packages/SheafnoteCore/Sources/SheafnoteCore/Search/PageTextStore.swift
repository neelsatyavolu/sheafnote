import Foundation
import SwiftData

/// Reads and writes the handwriting text kept on `Page`. The text syncs with the page, so another device that
/// sees a matching `ocrInkHash` never reads the same ink again.
@MainActor
public final class PageTextStore {
    private let context: ModelContext

    public init(context: ModelContext) { self.context = context }

    /// OCR bookkeeping for every live page of every live, unlocked notebook.
    public func ocrStates() throws -> [OCRPageState] {
        let notebooks = try context.fetch(FetchDescriptor<Notebook>(predicate: #Predicate { $0.deletedAt == nil }))
        let eligible = Set(notebooks.filter { !$0.isLocked && $0.kind != .text }.map(\.id))
        let pages = try context.fetch(FetchDescriptor<Page>(predicate: #Predicate { $0.deletedAt == nil }))
        return pages.filter { eligible.contains($0.notebookID) }.map {
            OCRPageState(pageID: $0.id, notebookID: $0.notebookID, inkHash: $0.inkHash, ocrInkHash: $0.ocrInkHash,
                         strokeCount: $0.strokeIDs.count, hasRecognizedText: !$0.recognizedText.isEmpty,
                         modifiedAt: $0.modifiedAt)
        }
    }

    /// Stores recognized text for ink that hashed to `inkHash`. If the page's ink changed while recognition ran,
    /// nothing is written and the page is read again later. Returns whether the text was stored.
    @discardableResult
    public func store(text: String, forInkHash inkHash: String, pageID: UUID, now: Date = .now) throws -> Bool {
        guard let page = try page(pageID), page.inkHash == inkHash else { return false }
        page.recognizedText = text
        page.ocrInkHash = inkHash
        markDirty(page, fields: ["recognizedText", "ocrInkHash"], now: now)
        try context.save()
        return true
    }

    /// Forgets the text of a page whose ink was cleared.
    @discardableResult
    public func clearText(forInkHash inkHash: String, pageID: UUID, now: Date = .now) throws -> Bool {
        try store(text: "", forInkHash: inkHash, pageID: pageID, now: now)
    }

    /// Forces every page to be read again (Settings, "Rebuild Search Index"). Ink is untouched.
    public func invalidateAll(now: Date = .now) throws -> Int {
        let pages = try context.fetch(FetchDescriptor<Page>(predicate: #Predicate { $0.deletedAt == nil && $0.ocrInkHash != "" }))
        for page in pages {
            page.ocrInkHash = ""
            markDirty(page, fields: ["ocrInkHash"], now: now)
        }
        try context.save()
        return pages.count
    }

    private func page(_ id: UUID) throws -> Page? {
        try context.fetch(FetchDescriptor<Page>(predicate: #Predicate { $0.id == id })).first
    }
}
