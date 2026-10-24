import Foundation
import SwiftData

@MainActor
public final class PageStore: AssetResolver {
    private let context: ModelContext
    private let revisions: RevisionStore

    public init(context: ModelContext, revisions: RevisionStore) {
        self.context = context
        self.revisions = revisions
    }

    // MARK: Reading

    public func orderedPages(of notebookID: UUID) throws -> [Page] {
        try context.fetch(FetchDescriptor<Page>(
            predicate: #Predicate { $0.notebookID == notebookID && $0.deletedAt == nil }))
            .sorted { SortKey.areInIncreasingOrder(($0.sortKey, $0.id), ($1.sortKey, $1.id)) }
    }

    public func page(id: UUID) -> Page? {
        try? context.fetch(FetchDescriptor<Page>(predicate: #Predicate { $0.id == id })).first
    }

    public func inkData(pageID: UUID) -> Data? { page(id: pageID)?.inkData }

    // MARK: Pages

    @discardableResult
    public func addPage(to notebookID: UUID, at position: PagePosition, template: TemplateSpec?, now: Date = .now) throws -> Page {
        let notebook = try requireNotebook(notebookID)
        let siblings = try orderedPages(of: notebookID)
        let key = sortKey(for: position, in: siblings)
        let page = Page(notebookID: notebookID, sortKey: key, size: notebook.pageSize,
                        isInfinite: notebook.kind == .whiteboard, now: now)
        page.template = template
        context.insert(page)
        markDirty(page, fields: ["sortKey", "widthPts", "heightPts", "templateOverride"], now: now)
        try context.save()
        return page
    }

    @discardableResult
    public func duplicate(pageID: UUID, now: Date = .now) throws -> Page {
        guard let source = page(id: pageID) else { throw StoreError.notFound("the page") }
        let siblings = try orderedPages(of: source.notebookID)
        let copy = Page(notebookID: source.notebookID, sortKey: sortKey(for: .after(pageID), in: siblings),
                        size: source.size, isInfinite: source.isInfinite, now: now)
        copy.templateOverride = source.templateOverride
        copy.paperColorOverride = source.paperColorOverride
        copy.backgroundAssetID = source.backgroundAssetID
        copy.backgroundPageIndex = source.backgroundPageIndex
        copy.inkData = source.inkData
        copy.strokeIDs = source.strokeIDs
        copy.inkHash = source.inkHash
        copy.recognizedText = source.recognizedText
        copy.ocrInkHash = source.ocrInkHash
        context.insert(copy)
        for element in try elements(on: pageID) {
            var v = element
            v.id = UUID()
            v.pageID = copy.id
            context.insert(PageElement(value: v, now: now))
        }
        markDirty(copy, fields: ["sortKey", "inkData", "strokeIDs", "inkHash"], now: now)
        try context.save()
        return copy
    }

    /// Soft delete. A recovery snapshot is taken first for every page.
    public func softDelete(pageIDs: [UUID], now: Date = .now) throws {
        for id in pageIDs {
            guard let page = page(id: id) else { continue }
            try revisions.snapshot(page: page, reason: .beforeDelete, now: now)
            page.deletedAt = now
            markDirty(page, fields: ["deletedAt"], now: now)
        }
        try context.save()
    }

    public func move(pageID: UUID, between previous: UUID?, and next: UUID?, now: Date = .now) throws {
        guard let page = page(id: pageID) else { throw StoreError.notFound("the page") }
        let prevKey = previous.flatMap { self.page(id: $0)?.sortKey }
        let nextKey = next.flatMap { self.page(id: $0)?.sortKey }
        page.sortKey = SortKey.between(prevKey, nextKey)
        markDirty(page, fields: ["sortKey"], now: now)
        try context.save()
    }

    // MARK: Ink

    /// Persists a page's ink. Clearing all ink snapshots the previous state first.
    public func saveInk(pageID: UUID, drawingData: Data, strokeIDs: [StrokeID], now: Date = .now) throws {
        guard let page = page(id: pageID) else { throw StoreError.notFound("the page") }
        if strokeIDs.isEmpty, !page.strokeIDs.isEmpty {
            try revisions.snapshot(page: page, reason: .beforeClear, now: now)
        }
        page.inkData = drawingData
        page.strokeIDs = strokeIDs.map(\.rawValue)
        page.inkHash = Hashing.sha256Hex(drawingData)
        markDirty(page, fields: ["inkData", "strokeIDs", "inkHash"], now: now)
        try context.save()
    }

    // MARK: Elements

    public func elements(on pageID: UUID) throws -> [ElementValue] {
        try context.fetch(FetchDescriptor<PageElement>(
            predicate: #Predicate { $0.pageID == pageID && $0.deletedAt == nil }))
            .map(\.value)
            .sorted { $0.zIndex == $1.zIndex ? $0.id.uuidString < $1.id.uuidString : $0.zIndex < $1.zIndex }
    }

    @discardableResult
    public func insertElement(_ value: ElementValue, now: Date = .now) throws -> ElementValue {
        let row = PageElement(value: value, now: now)
        context.insert(row)
        markDirty(row, fields: ["x", "y", "width", "height", "rotation", "zIndex", "payload", "assetID", "kind"], now: now)
        try context.save()
        return value
    }

    public func updateElement(id: UUID, now: Date = .now, _ mutate: (inout ElementValue) -> Void) throws {
        guard let row = try context.fetch(FetchDescriptor<PageElement>(predicate: #Predicate { $0.id == id })).first
        else { throw StoreError.notFound("the element") }
        var v = row.value
        mutate(&v)
        row.value = v
        markDirty(row, fields: ["x", "y", "width", "height", "rotation", "zIndex", "payload", "assetID"], now: now)
        try context.save()
    }

    public func softDeleteElements(ids: Set<UUID>, now: Date = .now) throws {
        let rows = try context.fetch(FetchDescriptor<PageElement>(predicate: #Predicate { ids.contains($0.id) }))
        for row in rows {
            row.deletedAt = now
            markDirty(row, fields: ["deletedAt"], now: now)
        }
        try context.save()
    }

    // MARK: Assets

    public func importAsset(data: Data, kind: AssetKind, filename: String?, uti: String? = nil, now: Date = .now) throws -> Asset {
        let hash = Hashing.sha256Hex(data)
        let existing = try context.fetch(FetchDescriptor<Asset>(
            predicate: #Predicate { $0.sha256 == hash && $0.deletedAt == nil }))
        if let match = existing.first(where: { $0.kind == kind }) { return match }
        let asset = Asset(kind: kind, data: data, sha256: hash, filename: filename, uti: uti, now: now)
        context.insert(asset)
        markDirty(asset, fields: ["kind", "data", "byteCount", "sha256", "filename", "uti"], now: now)
        try context.save()
        return asset
    }

    public func data(for assetID: UUID) async throws -> Data {
        guard let asset = try context.fetch(FetchDescriptor<Asset>(predicate: #Predicate { $0.id == assetID })).first
        else { throw StoreError.notFound("the attached file") }
        return asset.data
    }

    // MARK: Helpers

    private func requireNotebook(_ id: UUID) throws -> Notebook {
        guard let nb = try context.fetch(FetchDescriptor<Notebook>(predicate: #Predicate { $0.id == id })).first
        else { throw StoreError.notFound("the notebook") }
        return nb
    }

    private func sortKey(for position: PagePosition, in siblings: [Page]) -> String {
        switch position {
        case .end:
            return SortKey.between(siblings.last?.sortKey, nil)
        case .before(let id):
            guard let i = siblings.firstIndex(where: { $0.id == id }) else { return SortKey.between(siblings.last?.sortKey, nil) }
            return SortKey.between(i > 0 ? siblings[i - 1].sortKey : nil, siblings[i].sortKey)
        case .after(let id):
            guard let i = siblings.firstIndex(where: { $0.id == id }) else { return SortKey.between(siblings.last?.sortKey, nil) }
            return SortKey.between(siblings[i].sortKey, i + 1 < siblings.count ? siblings[i + 1].sortKey : nil)
        }
    }
}
