import CoreGraphics
import Foundation
import SwiftData

public struct PdfImportResult: Sendable, Equatable {
    public var notebookID: UUID
    public var pageIDs: [UUID]
    public var outlineEntryCount: Int
}

public struct ImportedImage: Sendable {
    public var data: Data
    public var filename: String?

    public init(data: Data, filename: String?) {
        self.data = data
        self.filename = filename
    }
}

/// Imports PDFs and images as notebook pages. The original file is stored once as an `Asset`; each page points at it
/// with `backgroundAssetID` (+ `backgroundPageIndex` for PDFs), so ink is a separate layer on top and the source file
/// is never modified. All rows are created in one transaction: a failure leaves the library as it was.
@MainActor
public struct PdfImporter {
    private let context: ModelContext
    private let pages: PageStore

    public init(context: ModelContext, pages: PageStore) {
        self.context = context
        self.pages = pages
    }

    // MARK: PDF

    /// A new notebook with one page per PDF page.
    public func importPDF(_ data: Data, title: String, into folderID: UUID?, now: Date = .now,
                          progress: (@MainActor (Double) -> Void)? = nil) async throws -> PdfImportResult {
        let source = try PDFSource(data: data)
        let asset = try pages.importAsset(data: data, kind: .pdf, filename: "\(title).pdf", uti: "com.adobe.pdf", now: now)
        let plans = (0..<source.pageCount).map { PagePlan(size: source.size(ofPage: $0), backgroundAssetID: asset.id, backgroundPageIndex: $0) }
        progress?(0.4)
        do {
            let notebook = try makeNotebook(title: title, firstPageSize: plans[0].size, in: folderID, now: now)
            let first = try pages.orderedPages(of: notebook.id).first
            let created = try PageInserter(context: context, pages: pages, now: now).insert(plans, into: notebook.id, at: .end, reuse: first)
            let outline = try importOutline(source.outline(), notebookID: notebook.id, pageIDs: created.map(\.id), now: now)
            notebook.pdfOutlineImported = true
            try context.save()
            progress?(1)
            return PdfImportResult(notebookID: notebook.id, pageIDs: created.map(\.id), outlineEntryCount: outline)
        } catch {
            context.rollback()
            throw error
        }
    }

    /// Inserts every page of a PDF into an existing notebook.
    public func insertPDF(_ data: Data, filename: String?, into notebookID: UUID, at position: PagePosition,
                          now: Date = .now) async throws -> PdfImportResult {
        let notebook = try requirePagedNotebook(notebookID)
        let source = try PDFSource(data: data)
        let asset = try pages.importAsset(data: data, kind: .pdf, filename: filename, uti: "com.adobe.pdf", now: now)
        let plans = (0..<source.pageCount).map { PagePlan(size: source.size(ofPage: $0), backgroundAssetID: asset.id, backgroundPageIndex: $0) }
        do {
            let created = try PageInserter(context: context, pages: pages, now: now).insert(plans, into: notebookID, at: position)
            let outline = try importOutline(source.outline(), notebookID: notebookID, pageIDs: created.map(\.id), now: now)
            if outline > 0 {
                notebook.pdfOutlineImported = true
                markDirty(notebook, fields: ["pdfOutlineImported"], now: now)
            }
            try context.save()
            return PdfImportResult(notebookID: notebookID, pageIDs: created.map(\.id), outlineEntryCount: outline)
        } catch {
            context.rollback()
            throw error
        }
    }

    // MARK: Images

    /// A new notebook with one page per image.
    public func importImages(_ images: [ImportedImage], title: String, into folderID: UUID?, now: Date = .now) async throws -> PdfImportResult {
        guard !images.isEmpty else { throw PdfIOError.nothingToImport }
        let plans = try imagePlans(images, now: now)
        do {
            let notebook = try makeNotebook(title: title, firstPageSize: plans[0].size, in: folderID, now: now)
            let first = try pages.orderedPages(of: notebook.id).first
            let created = try PageInserter(context: context, pages: pages, now: now).insert(plans, into: notebook.id, at: .end, reuse: first)
            try context.save()
            return PdfImportResult(notebookID: notebook.id, pageIDs: created.map(\.id), outlineEntryCount: 0)
        } catch {
            context.rollback()
            throw error
        }
    }

    /// Inserts one page per image into an existing notebook.
    public func insertImages(_ images: [ImportedImage], into notebookID: UUID, at position: PagePosition,
                             now: Date = .now) async throws -> PdfImportResult {
        guard !images.isEmpty else { throw PdfIOError.nothingToImport }
        _ = try requirePagedNotebook(notebookID)
        let plans = try imagePlans(images, now: now)
        do {
            let created = try PageInserter(context: context, pages: pages, now: now).insert(plans, into: notebookID, at: position)
            try context.save()
            return PdfImportResult(notebookID: notebookID, pageIDs: created.map(\.id), outlineEntryCount: 0)
        } catch {
            context.rollback()
            throw error
        }
    }

    // MARK: Helpers

    private func imagePlans(_ images: [ImportedImage], now: Date) throws -> [PagePlan] {
        try images.map { image in
            let source = try ImagePageSource(data: image.data, name: image.filename ?? "image")
            let asset = try pages.importAsset(data: image.data, kind: .image, filename: image.filename, now: now)
            return PagePlan(size: ImagePageSource.pageSize(forPixels: source.pixelSize), backgroundAssetID: asset.id, backgroundPageIndex: nil)
        }
    }

    private func requirePagedNotebook(_ id: UUID) throws -> Notebook {
        guard let notebook = try context.fetch(FetchDescriptor<Notebook>(predicate: #Predicate { $0.id == id && $0.deletedAt == nil })).first
        else { throw PdfIOError.notebookMissing }
        guard notebook.kind == .paged else { throw PdfIOError.notAPagedNotebook }
        return notebook
    }

    /// Creates the notebook with its paper settings matched to the first page, and one blank page for the inserter to reuse.
    private func makeNotebook(title: String, firstPageSize: CGSize, in folderID: UUID?, now: Date) throws -> Notebook {
        let size = Self.closestPaper(to: firstPageSize)
        let last = try context.fetch(FetchDescriptor<Notebook>(predicate: #Predicate { $0.folderID == folderID && $0.deletedAt == nil }))
            .sorted { SortKey.areInIncreasingOrder(($0.sortKey, $0.id), ($1.sortKey, $1.id)) }.last
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let notebook = Notebook(title: name.isEmpty ? "Imported" : name, kind: .paged, folderID: folderID,
                                cover: CoverSpec(coverID: "graphite"), template: .blank, paperSize: size.paper,
                                orientation: size.orientation, paperColor: .white,
                                sortKey: SortKey.between(last?.sortKey, nil), now: now)
        context.insert(notebook)
        let page = Page(notebookID: notebook.id, sortKey: SortKey.between(nil, nil), size: firstPageSize, now: now)
        context.insert(page)
        markDirty(notebook, fields: LibraryStore.notebookFields, now: now)
        markDirty(page, fields: LibraryStore.pageFields, now: now)
        return notebook
    }

    static func closestPaper(to size: CGSize) -> (paper: PaperSize, orientation: PageOrientation) {
        let orientation: PageOrientation = size.width > size.height ? .landscape : .portrait
        let aspect = min(size.width, size.height) / max(size.width, size.height)
        let best = PaperSize.allCases.min { abs(ratio($0) - aspect) < abs(ratio($1) - aspect) } ?? .a4
        return (best, best.supportsOrientation ? orientation : .portrait)
    }

    private static func ratio(_ paper: PaperSize) -> CGFloat {
        let s = paper.portraitSize
        return s.width / s.height
    }

    private func importOutline(_ items: [PDFOutlineItem], notebookID: UUID, pageIDs: [UUID], now: Date) throws -> Int {
        guard !items.isEmpty else { return 0 }
        let existing = try context.fetch(FetchDescriptor<OutlineEntry>(predicate: #Predicate { $0.notebookID == notebookID && $0.deletedAt == nil }))
        let lower = existing.map(\.sortKey).max()
        let keys = SortKey.spread(items.count, between: lower, and: nil)
        let rowIDs = items.map { _ in UUID() }
        for (i, item) in items.enumerated() {
            let pageIndex = item.pageIndex.flatMap { pageIDs.indices.contains($0) ? $0 : nil }
            let row = OutlineEntry(id: rowIDs[i], notebookID: notebookID, title: item.title,
                                   pageID: pageIndex.map { pageIDs[$0] }, pdfPageIndex: item.pageIndex,
                                   parentID: item.parent.map { rowIDs[$0] }, sortKey: keys[i], source: .pdf, now: now)
            context.insert(row)
            markDirty(row, fields: ["notebookID", "title", "pageID", "pdfPageIndex", "parentID", "sortKey", "source"], now: now)
        }
        return items.count
    }
}
