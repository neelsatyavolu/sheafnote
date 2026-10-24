import Foundation
import SwiftData

@Model
public final class Asset: SyncableRecord {
    @Attribute(.unique) public var id: UUID
    public var createdAt: Date
    public var modifiedAt: Date
    public var deletedAt: Date?
    public var syncDirty: Bool
    public var dirtyFields: [String]
    public var ckSystemFields: Data?
    public var formatVersion: Int

    public var kind: AssetKind
    @Attribute(.externalStorage) public var data: Data
    public var byteCount: Int
    public var sha256: String
    public var filename: String?
    public var uti: String?

    public static var recordType: String { "SNAsset" }

    public init(id: UUID = UUID(), kind: AssetKind, data: Data, sha256: String,
                filename: String? = nil, uti: String? = nil, now: Date = .now) {
        self.id = id
        self.createdAt = now
        self.modifiedAt = now
        self.deletedAt = nil
        self.syncDirty = true
        self.dirtyFields = []
        self.ckSystemFields = nil
        self.formatVersion = SchemaFormat.currentVersion
        self.kind = kind
        self.data = data
        self.byteCount = data.count
        self.sha256 = sha256
        self.filename = filename
        self.uti = uti
    }
}
