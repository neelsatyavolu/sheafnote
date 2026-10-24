import Foundation
import SwiftData

@Model
public final class Bookmark: SyncableRecord {
    @Attribute(.unique) public var id: UUID
    public var createdAt: Date
    public var modifiedAt: Date
    public var deletedAt: Date?
    public var syncDirty: Bool
    public var dirtyFields: [String]
    public var ckSystemFields: Data?
    public var formatVersion: Int

    public var notebookID: UUID
    public var pageID: UUID
    public var title: String?

    public static var recordType: String { "SNBookmark" }

    public init(id: UUID = UUID(), notebookID: UUID, pageID: UUID, title: String? = nil, now: Date = .now) {
        self.id = id
        self.createdAt = now
        self.modifiedAt = now
        self.deletedAt = nil
        self.syncDirty = true
        self.dirtyFields = []
        self.ckSystemFields = nil
        self.formatVersion = SchemaFormat.currentVersion
        self.notebookID = notebookID
        self.pageID = pageID
        self.title = title
    }
}
