import Foundation
import SwiftData

@Model
public final class Flashcard: SyncableRecord {
    @Attribute(.unique) public var id: UUID
    public var createdAt: Date
    public var modifiedAt: Date
    public var deletedAt: Date?
    public var syncDirty: Bool
    public var dirtyFields: [String]
    public var ckSystemFields: Data?
    public var formatVersion: Int

    public var notebookID: UUID
    public var deck: String
    public var sourcePageID: UUID?
    @Attribute(.externalStorage) public var frontImage: Data
    @Attribute(.externalStorage) public var backImage: Data
    public var frontText: String?
    public var backText: String?

    public static var recordType: String { "SNFlashcard" }

    public init(id: UUID = UUID(), notebookID: UUID, deck: String, sourcePageID: UUID? = nil,
                frontImage: Data, backImage: Data, frontText: String? = nil, backText: String? = nil, now: Date = .now) {
        self.id = id
        self.createdAt = now
        self.modifiedAt = now
        self.deletedAt = nil
        self.syncDirty = true
        self.dirtyFields = []
        self.ckSystemFields = nil
        self.formatVersion = SchemaFormat.currentVersion
        self.notebookID = notebookID
        self.deck = deck
        self.sourcePageID = sourcePageID
        self.frontImage = frontImage
        self.backImage = backImage
        self.frontText = frontText
        self.backText = backText
    }
}
