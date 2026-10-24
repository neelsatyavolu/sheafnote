import Foundation
import SwiftData

@Model
public final class Folder: SyncableRecord {
    @Attribute(.unique) public var id: UUID
    public var createdAt: Date
    public var modifiedAt: Date
    public var deletedAt: Date?
    public var syncDirty: Bool
    public var dirtyFields: [String]
    public var ckSystemFields: Data?
    public var formatVersion: Int

    public var name: String
    public var parentID: UUID?
    public var sortKey: String
    public var isFavorite: Bool
    public var colorName: String?

    public static var recordType: String { "SNFolder" }

    public init(id: UUID = UUID(), name: String, parentID: UUID?, sortKey: String,
                isFavorite: Bool = false, colorName: String? = nil, now: Date = .now) {
        self.id = id
        self.createdAt = now
        self.modifiedAt = now
        self.deletedAt = nil
        self.syncDirty = true
        self.dirtyFields = []
        self.ckSystemFields = nil
        self.formatVersion = SchemaFormat.currentVersion
        self.name = name
        self.parentID = parentID
        self.sortKey = sortKey
        self.isFavorite = isFavorite
        self.colorName = colorName
    }
}
