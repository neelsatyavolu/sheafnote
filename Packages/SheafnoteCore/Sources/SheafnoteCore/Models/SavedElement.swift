import Foundation
import SwiftData

@Model
public final class SavedElement: SyncableRecord {
    @Attribute(.unique) public var id: UUID
    public var createdAt: Date
    public var modifiedAt: Date
    public var deletedAt: Date?
    public var syncDirty: Bool
    public var dirtyFields: [String]
    public var ckSystemFields: Data?
    public var formatVersion: Int

    public var name: String
    public var category: String
    public var width: Double
    public var height: Double
    @Attribute(.externalStorage) public var inkData: Data?
    /// JSON `[ElementValue]`
    public var elements: Data
    @Attribute(.externalStorage) public var thumbnail: Data

    public static var recordType: String { "SNSavedElement" }

    public init(id: UUID = UUID(), name: String, category: String, width: Double, height: Double,
                inkData: Data?, elements: Data, thumbnail: Data, now: Date = .now) {
        self.id = id
        self.createdAt = now
        self.modifiedAt = now
        self.deletedAt = nil
        self.syncDirty = true
        self.dirtyFields = []
        self.ckSystemFields = nil
        self.formatVersion = SchemaFormat.currentVersion
        self.name = name
        self.category = category
        self.width = width
        self.height = height
        self.inkData = inkData
        self.elements = elements
        self.thumbnail = thumbnail
    }
}
