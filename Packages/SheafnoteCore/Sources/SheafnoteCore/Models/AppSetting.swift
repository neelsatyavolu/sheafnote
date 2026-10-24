import Foundation
import SwiftData

@Model
public final class AppSetting: SyncableRecord {
    @Attribute(.unique) public var id: UUID
    public var createdAt: Date
    public var modifiedAt: Date
    public var deletedAt: Date?
    public var syncDirty: Bool
    public var dirtyFields: [String]
    public var ckSystemFields: Data?
    public var formatVersion: Int

    public var key: String
    public var valueJSON: Data

    public static var recordType: String { "SNSetting" }

    public init(id: UUID, key: String, valueJSON: Data, now: Date = .now) {
        self.id = id
        self.createdAt = now
        self.modifiedAt = now
        self.deletedAt = nil
        self.syncDirty = true
        self.dirtyFields = []
        self.ckSystemFields = nil
        self.formatVersion = SchemaFormat.currentVersion
        self.key = key
        self.valueJSON = valueJSON
    }
}
