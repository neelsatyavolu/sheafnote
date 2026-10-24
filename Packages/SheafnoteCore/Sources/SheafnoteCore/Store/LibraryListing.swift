import Foundation

public enum LibraryScope: Hashable, Sendable {
    case documents          // top level
    case folder(UUID)
    case favorites
    case recentlyDeleted
}

public enum LibrarySortField: String, CaseIterable, Sendable, Codable { case name, created, modified }

public struct LibrarySort: Hashable, Sendable, Codable {
    public var field: LibrarySortField
    public var ascending: Bool

    public init(field: LibrarySortField = .modified, ascending: Bool = false) {
        self.field = field
        self.ascending = ascending
    }
}

public enum LibraryEntry: Identifiable, Hashable {
    case folder(Folder)
    case notebook(Notebook)

    public var ref: LibraryItemRef {
        switch self {
        case .folder(let f): .folder(f.id)
        case .notebook(let n): .notebook(n.id)
        }
    }
    public var id: UUID { ref.id }
    public var title: String {
        switch self {
        case .folder(let f): f.name
        case .notebook(let n): n.title
        }
    }
    public var createdAt: Date {
        switch self {
        case .folder(let f): f.createdAt
        case .notebook(let n): n.createdAt
        }
    }
    public var modifiedAt: Date {
        switch self {
        case .folder(let f): f.modifiedAt
        case .notebook(let n): n.modifiedAt
        }
    }
    public var deletedAt: Date? {
        switch self {
        case .folder(let f): f.deletedAt
        case .notebook(let n): n.deletedAt
        }
    }
    public var isFavorite: Bool {
        switch self {
        case .folder(let f): f.isFavorite
        case .notebook(let n): n.isFavorite
        }
    }
}

/// Pure filtering/sorting of library rows for the UI. Testable without a view.
public enum LibraryListing {
    public static func entries(scope: LibraryScope, folders: [Folder], notebooks: [Notebook],
                               sort: LibrarySort, now: Date = .now) -> [LibraryEntry] {
        switch scope {
        case .documents:
            return ordered(folders.filter { $0.deletedAt == nil && $0.parentID == nil }.map(LibraryEntry.folder),
                           notebooks.filter { $0.deletedAt == nil && $0.folderID == nil }.map(LibraryEntry.notebook), sort)
        case .folder(let id):
            return ordered(folders.filter { $0.deletedAt == nil && $0.parentID == id }.map(LibraryEntry.folder),
                           notebooks.filter { $0.deletedAt == nil && $0.folderID == id }.map(LibraryEntry.notebook), sort)
        case .favorites:
            return ordered(folders.filter { $0.deletedAt == nil && $0.isFavorite }.map(LibraryEntry.folder),
                           notebooks.filter { $0.deletedAt == nil && $0.isFavorite }.map(LibraryEntry.notebook), sort)
        case .recentlyDeleted:
            return trash(folders: folders, notebooks: notebooks)
        }
    }

    /// Top-level trash items: deleted, and not simply carried along by a deleted parent folder.
    public static func trash(folders: [Folder], notebooks: [Notebook]) -> [LibraryEntry] {
        let byID = Dictionary(uniqueKeysWithValues: folders.map { ($0.id, $0) })
        func carried(_ parent: UUID?, _ stamp: Date?) -> Bool {
            guard let parent, let p = byID[parent], let pd = p.deletedAt else { return false }
            return pd == stamp
        }
        let fs = folders.filter { $0.deletedAt != nil && !carried($0.parentID, $0.deletedAt) }.map(LibraryEntry.folder)
        let ns = notebooks.filter { $0.deletedAt != nil && !carried($0.folderID, $0.deletedAt) }.map(LibraryEntry.notebook)
        return (fs + ns).sorted { ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast) }
    }

    /// Case- and diacritic-insensitive title search over live items.
    public static func search(_ query: String, folders: [Folder], notebooks: [Notebook]) -> [LibraryEntry] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        func hit(_ s: String) -> Bool { s.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        return folders.filter { $0.deletedAt == nil && hit($0.name) }.map(LibraryEntry.folder)
            + notebooks.filter { $0.deletedAt == nil && hit($0.title) }.map(LibraryEntry.notebook)
    }

    public static func daysRemaining(deletedAt: Date, now: Date = .now) -> Int {
        let remaining = deletedAt.addingTimeInterval(Retention.seconds).timeIntervalSince(now)
        return max(0, Int((remaining / 86_400).rounded(.up)))
    }

    /// Folder chain from the top level down to `id`, for breadcrumbs and pickers.
    public static func path(to id: UUID, folders: [Folder]) -> [Folder] {
        var chain: [Folder] = []
        var current: UUID? = id
        var guardCount = 0
        while let cid = current, let f = folders.first(where: { $0.id == cid }), guardCount < 64 {
            chain.insert(f, at: 0)
            current = f.parentID
            guardCount += 1
        }
        return chain
    }

    public static func childCount(of folderID: UUID, folders: [Folder], notebooks: [Notebook]) -> Int {
        folders.filter { $0.deletedAt == nil && $0.parentID == folderID }.count
            + notebooks.filter { $0.deletedAt == nil && $0.folderID == folderID }.count
    }

    private static func ordered(_ fs: [LibraryEntry], _ ns: [LibraryEntry], _ sort: LibrarySort) -> [LibraryEntry] {
        sorted(fs, sort) + sorted(ns, sort)
    }

    public static func sorted(_ entries: [LibraryEntry], _ sort: LibrarySort) -> [LibraryEntry] {
        entries.sorted { a, b in
            let result: ComparisonResult
            switch sort.field {
            case .name: result = a.title.localizedStandardCompare(b.title)
            case .created: result = a.createdAt.compare(b.createdAt)
            case .modified: result = a.modifiedAt.compare(b.modifiedAt)
            }
            if result == .orderedSame { return a.id.uuidString < b.id.uuidString }
            return sort.ascending ? result == .orderedAscending : result == .orderedDescending
        }
    }
}
