import Foundation

/// Which part of a page or title a piece of searchable text came from. Higher weight ranks higher.
public enum SearchField: Int, CaseIterable, Sendable, Hashable {
    case title, typed, handwriting, pdf

    public var weight: Double {
        switch self {
        case .title: 4
        case .typed: 2
        case .handwriting: 1.5
        case .pdf: 1
        }
    }
}

public struct SearchDocumentID: Hashable, Sendable {
    public enum Kind: Int, Sendable { case notebookTitle, folderTitle, page, textDocument }

    public let kind: Kind
    public let id: UUID

    public init(kind: Kind, id: UUID) {
        self.kind = kind
        self.id = id
    }
}

/// Everything searchable about one thing: a title, one page, or a text document.
public struct SearchDocument: Sendable, Hashable {
    public var id: SearchDocumentID
    /// The notebook this belongs to (itself for a notebook title).
    public var notebookID: UUID?
    public var fields: [SearchField: String]
    public var modifiedAt: Date
    /// Changes whenever the text may have changed; lets a refresh skip unchanged documents.
    public var fingerprint: String

    public init(id: SearchDocumentID, notebookID: UUID?, fields: [SearchField: String],
                modifiedAt: Date, fingerprint: String) {
        self.id = id
        self.notebookID = notebookID
        self.fields = fields
        self.modifiedAt = modifiedAt
        self.fingerprint = fingerprint
    }
}

/// A short piece of text around a match. `ranges` are character offsets into `text`.
public struct SearchSnippet: Sendable, Hashable {
    public var text: String
    public var ranges: [Range<Int>]

    public init(text: String, ranges: [Range<Int>]) {
        self.text = text
        self.ranges = ranges
    }
}

public struct SearchHit: Sendable, Hashable, Identifiable {
    public var id: SearchDocumentID { documentID }
    public let documentID: SearchDocumentID
    public let notebookID: UUID?
    /// The field the snippet came from (the best-scoring one).
    public let field: SearchField
    public let score: Double
    public let snippet: SearchSnippet
    /// Normalized query terms; used to place highlight rectangles on a page.
    public let terms: [String]
}
