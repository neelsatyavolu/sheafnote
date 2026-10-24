import Foundation

/// Value copy of an `OutlineEntry`.
public struct OutlineItem: Sendable, Hashable, Identifiable {
    public var id: UUID
    public var title: String
    public var pageID: UUID?
    public var pdfPageIndex: Int?
    public var parentID: UUID?
    public var sortKey: String
    public var source: OutlineSource

    public init(id: UUID, title: String, pageID: UUID?, pdfPageIndex: Int?, parentID: UUID?,
                sortKey: String, source: OutlineSource) {
        self.id = id
        self.title = title
        self.pageID = pageID
        self.pdfPageIndex = pdfPageIndex
        self.parentID = parentID
        self.sortKey = sortKey
        self.source = source
    }

    public init(_ entry: OutlineEntry) {
        self.init(id: entry.id, title: entry.title, pageID: entry.pageID, pdfPageIndex: entry.pdfPageIndex,
                  parentID: entry.parentID, sortKey: entry.sortKey,
                  source: OutlineSource(rawValue: entry.source) ?? .user)
    }
}

public struct OutlineRow: Sendable, Hashable, Identifiable {
    public var item: OutlineItem
    public var depth: Int
    public var id: UUID { item.id }
}

/// A notebook page and, for pages that came from a PDF, which PDF page it shows.
public struct OutlinePageRef: Sendable, Hashable {
    public var id: UUID
    public var pdfPageIndex: Int?

    public init(id: UUID, pdfPageIndex: Int?) {
        self.id = id
        self.pdfPageIndex = pdfPageIndex
    }
}

public enum OutlineTree {
    /// Flattens entries depth-first for display. Siblings follow `sortKey`; an entry whose parent is missing is
    /// shown at the top level; a parent cycle is cut so no entry is ever hidden.
    public static func rows(from items: [OutlineItem]) -> [OutlineRow] {
        let byID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var children: [UUID?: [OutlineItem]] = [:]
        for item in items {
            let parent = item.parentID.flatMap { byID[$0] != nil ? $0 : nil }
            children[parent, default: []].append(item)
        }
        var rows: [OutlineRow] = []
        var visited = Set<UUID>()
        func walk(_ parent: UUID?, depth: Int) {
            for item in sorted(children[parent] ?? []) where visited.insert(item.id).inserted {
                rows.append(OutlineRow(item: item, depth: depth))
                walk(item.id, depth: depth + 1)
            }
        }
        walk(nil, depth: 0)
        for item in sorted(items) where !visited.contains(item.id) {
            visited.insert(item.id)
            rows.append(OutlineRow(item: item, depth: 0))
            walk(item.id, depth: 1)
        }
        return rows
    }

    /// The notebook page an entry jumps to: its own page if that page still exists, else the page showing its PDF page.
    public static func targetPage(of item: OutlineItem, in pages: [OutlinePageRef]) -> UUID? {
        if let id = item.pageID, pages.contains(where: { $0.id == id }) { return id }
        guard let index = item.pdfPageIndex else { return nil }
        return pages.first { $0.pdfPageIndex == index }?.id
    }

    public static func descendantIDs(of id: UUID, in items: [OutlineItem]) -> Set<UUID> {
        var found = Set<UUID>()
        var frontier = [id]
        while let current = frontier.popLast() {
            for child in items where child.parentID == current && child.id != id && found.insert(child.id).inserted {
                frontier.append(child.id)
            }
        }
        return found
    }

    private static func sorted(_ items: [OutlineItem]) -> [OutlineItem] {
        items.sorted { SortKey.areInIncreasingOrder(($0.sortKey, $0.id), ($1.sortKey, $1.id)) }
    }
}
