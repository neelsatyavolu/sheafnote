import Foundation
import SwiftData

@Model
public final class OutlineEntry: SyncableRecord {
    @Attribute(.unique) public var id: UUID
    public var createdAt: Date
    public var modifiedAt: Date
    public var deletedAt: Date?
    public var syncDirty: Bool
    public var dirtyFields: [String]
    public var ckSystemFields: Data?
    public var formatVersion: Int

    public var notebookID: UUID
    public var title: String
    public var pageID: UUID?
    public var pdfPageIndex: Int?
    public var parentID: UUID?
    public var sortKey: String
    public var source: String

    public static var recordType: String { "SNOutlineEntry" }

    public init(id: UUID = UUID(), notebookID: UUID, title: String, pageID: UUID?, pdfPageIndex: Int? = nil,
                parentID: UUID? = nil, sortKey: String, source: OutlineSource = .user, now: Date = .now) {
        self.id = id
        self.createdAt = now
        self.modifiedAt = now
        self.deletedAt = nil
        self.syncDirty = true
        self.dirtyFields = []
        self.ckSystemFields = nil
        self.formatVersion = SchemaFormat.currentVersion
        self.notebookID = notebookID
        self.title = title
        self.pageID = pageID
        self.pdfPageIndex = pdfPageIndex
        self.parentID = parentID
        self.sortKey = sortKey
        self.source = source.rawValue
    }
}
