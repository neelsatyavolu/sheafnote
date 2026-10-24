import Foundation
import SwiftData

/// Text pulled out of imported PDFs, one string per PDF page, keyed by the PDF asset's id.
public typealias PDFTextCache = [UUID: [String]]

public struct CorpusRefresh: Sendable, Equatable {
    public var updated = 0
    public var removed = 0
}

/// Builds `SearchDocument`s from the library and keeps a `SearchIndex` current. Pages in locked notebooks are
/// left out of the index (their titles stay searchable, like their covers stay visible).
@MainActor
public final class SearchCorpus {
    private let context: ModelContext

    public init(context: ModelContext) { self.context = context }

    /// PDF assets used as page backgrounds in live, unlocked notebooks that are not in `cache` yet.
    public func missingPDFAssets(cache: PDFTextCache) throws -> Set<UUID> {
        let live = try liveNotebooks().filter { !$0.isLocked }
        let ids = Set(live.map(\.id))
        let pages = try context.fetch(FetchDescriptor<Page>(predicate: #Predicate { $0.deletedAt == nil && $0.backgroundAssetID != nil }))
        let used = pages.filter { ids.contains($0.notebookID) }.compactMap(\.backgroundAssetID)
        return Set(used).subtracting(cache.keys)
    }

    /// Adds, updates and removes documents so `index` matches the library. Unchanged documents are skipped.
    @discardableResult
    public func refresh(_ index: inout SearchIndex, pdfTexts: PDFTextCache = [:]) throws -> CorpusRefresh {
        var report = CorpusRefresh()
        var alive = Set<SearchDocumentID>()
        func put(_ doc: SearchDocument) {
            alive.insert(doc.id)
            guard index.fingerprint(of: doc.id) != doc.fingerprint else { return }
            index.upsert(doc)
            report.updated += 1
        }
        let notebooks = try liveNotebooks()
        for folder in try context.fetch(FetchDescriptor<Folder>(predicate: #Predicate { $0.deletedAt == nil })) {
            put(titleDocument(.folderTitle, id: folder.id, title: folder.name, notebookID: nil, modifiedAt: folder.modifiedAt))
        }
        for notebook in notebooks {
            put(titleDocument(.notebookTitle, id: notebook.id, title: notebook.title, notebookID: notebook.id,
                              modifiedAt: notebook.modifiedAt))
            if notebook.kind == .text { putTextDocument(notebook, put) }
        }
        try putPages(notebooks: notebooks.filter { !$0.isLocked && $0.kind != .text }, pdfTexts: pdfTexts, put)
        let stale = index.count
        index.retainOnly(ids: alive)
        report.removed = stale - index.count
        return report
    }

    // MARK: Documents

    private func liveNotebooks() throws -> [Notebook] {
        try context.fetch(FetchDescriptor<Notebook>(predicate: #Predicate { $0.deletedAt == nil }))
    }

    private func titleDocument(_ kind: SearchDocumentID.Kind, id: UUID, title: String, notebookID: UUID?,
                               modifiedAt: Date) -> SearchDocument {
        SearchDocument(id: SearchDocumentID(kind: kind, id: id), notebookID: notebookID, fields: [.title: title],
                       modifiedAt: modifiedAt, fingerprint: "t|\(title)")
    }

    private func putTextDocument(_ notebook: Notebook, _ put: (SearchDocument) -> Void) {
        guard !notebook.isLocked, let data = notebook.richText else { return }
        let text = RichTextExtractor.plainText(fromJSON: data)
        put(SearchDocument(id: SearchDocumentID(kind: .textDocument, id: notebook.id), notebookID: notebook.id,
                           fields: [.typed: text], modifiedAt: notebook.modifiedAt,
                           fingerprint: "r|\(notebook.modifiedAt.timeIntervalSinceReferenceDate)|\(data.count)"))
    }

    private func putPages(notebooks: [Notebook], pdfTexts: PDFTextCache, _ put: (SearchDocument) -> Void) throws {
        let ids = Set(notebooks.map(\.id))
        let pages = try context.fetch(FetchDescriptor<Page>(predicate: #Predicate { $0.deletedAt == nil }))
            .filter { ids.contains($0.notebookID) }
        let typed = try typedText(forPages: Set(pages.map(\.id)))
        for page in pages {
            let extra = typed[page.id]
            let pdf = pdfText(for: page, in: pdfTexts)
            let fingerprint = "p|\(page.modifiedAt.timeIntervalSinceReferenceDate)|\(page.ocrInkHash)|\(extra?.fingerprint ?? "-")|\(pdf?.count ?? -1)"
            var fields: [SearchField: String] = [:]
            if !page.recognizedText.isEmpty { fields[.handwriting] = page.recognizedText }
            if let extra, !extra.text.isEmpty { fields[.typed] = extra.text }
            if let pdf, !pdf.isEmpty { fields[.pdf] = pdf }
            put(SearchDocument(id: SearchDocumentID(kind: .page, id: page.id), notebookID: page.notebookID,
                               fields: fields, modifiedAt: page.modifiedAt, fingerprint: fingerprint))
        }
    }

    private func pdfText(for page: Page, in cache: PDFTextCache) -> String? {
        guard let asset = page.backgroundAssetID, let index = page.backgroundPageIndex,
              let texts = cache[asset], texts.indices.contains(index) else { return nil }
        return texts[index]
    }

    /// Typed text of text boxes and link labels, per page, with a fingerprint of the elements it came from.
    private func typedText(forPages ids: Set<UUID>) throws -> [UUID: (text: String, fingerprint: String)] {
        let elements = try context.fetch(FetchDescriptor<PageElement>(predicate: #Predicate { $0.deletedAt == nil }))
        var grouped: [UUID: [PageElement]] = [:]
        for element in elements where ids.contains(element.pageID) && (element.kind == .text || element.kind == .link) {
            grouped[element.pageID, default: []].append(element)
        }
        return grouped.mapValues { rows in
            let ordered = rows.sorted { ($0.zIndex, $0.id.uuidString) < ($1.zIndex, $1.id.uuidString) }
            let text = ordered.compactMap(Self.text(of:)).joined(separator: "\n")
            let latest = rows.map(\.modifiedAt).max()?.timeIntervalSinceReferenceDate ?? 0
            return (text, "\(rows.count)@\(latest)")
        }
    }

    private static func text(of element: PageElement) -> String? {
        switch element.kind {
        case .text: PayloadCodec.decode(TextPayload.self, from: element.payload)?.text
        case .link: PayloadCodec.decode(LinkPayload.self, from: element.payload)?.label
        default: nil
        }
    }
}
