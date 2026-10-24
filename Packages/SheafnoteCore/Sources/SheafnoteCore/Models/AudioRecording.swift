import Foundation
import SwiftData

@Model
public final class AudioRecording: SyncableRecord {
    @Attribute(.unique) public var id: UUID
    public var createdAt: Date
    public var modifiedAt: Date
    public var deletedAt: Date?
    public var syncDirty: Bool
    public var dirtyFields: [String]
    public var ckSystemFields: Data?
    public var formatVersion: Int

    public var notebookID: UUID
    public var assetID: UUID
    public var title: String
    public var startedAt: Date
    public var duration: Double
    /// JSON `[AudioStrokeMark]` (pageID, strokeID, offset seconds); owned by audio-study.
    public var timeline: Data

    public static var recordType: String { "SNAudioRecording" }

    public init(id: UUID = UUID(), notebookID: UUID, assetID: UUID, title: String, startedAt: Date,
                duration: Double, timeline: Data = Data(), now: Date = .now) {
        self.id = id
        self.createdAt = now
        self.modifiedAt = now
        self.deletedAt = nil
        self.syncDirty = true
        self.dirtyFields = []
        self.ckSystemFields = nil
        self.formatVersion = SchemaFormat.currentVersion
        self.notebookID = notebookID
        self.assetID = assetID
        self.title = title
        self.startedAt = startedAt
        self.duration = duration
        self.timeline = timeline
    }
}
