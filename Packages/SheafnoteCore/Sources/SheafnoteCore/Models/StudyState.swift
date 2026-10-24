import Foundation
import SwiftData

@Model
public final class StudyState: SyncableRecord {
    @Attribute(.unique) public var id: UUID
    public var createdAt: Date
    public var modifiedAt: Date
    public var deletedAt: Date?
    public var syncDirty: Bool
    public var dirtyFields: [String]
    public var ckSystemFields: Data?
    public var formatVersion: Int

    public var flashcardID: UUID
    public var ease: Double
    public var intervalDays: Int
    public var repetitions: Int
    public var lapses: Int
    public var dueAt: Date
    public var lastReviewedAt: Date?

    public static var recordType: String { "SNStudyState" }

    public init(id: UUID = UUID(), flashcardID: UUID, dueAt: Date = .now, now: Date = .now) {
        self.id = id
        self.createdAt = now
        self.modifiedAt = now
        self.deletedAt = nil
        self.syncDirty = true
        self.dirtyFields = []
        self.ckSystemFields = nil
        self.formatVersion = SchemaFormat.currentVersion
        self.flashcardID = flashcardID
        self.ease = 2.5
        self.intervalDays = 0
        self.repetitions = 0
        self.lapses = 0
        self.dueAt = dueAt
        self.lastReviewedAt = nil
    }
}
