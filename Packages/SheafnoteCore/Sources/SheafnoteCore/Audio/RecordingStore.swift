import Foundation
import SwiftData

/// Audio recordings of a notebook: the audio bytes live in an `Asset(.audio)`, the metadata and stroke timeline in
/// `AudioRecording`. Delete is soft and keeps the asset, so a recording can be brought back.
@MainActor
public final class RecordingStore {
    private let context: ModelContext

    public init(context: ModelContext) { self.context = context }

    public func recordings(in notebookID: UUID) throws -> [AudioRecording] {
        try context.fetch(FetchDescriptor<AudioRecording>(
            predicate: #Predicate { $0.notebookID == notebookID && $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse), SortDescriptor(\.id)]))
    }

    public func recording(id: UUID) throws -> AudioRecording? {
        try context.fetch(FetchDescriptor<AudioRecording>(predicate: #Predicate { $0.id == id && $0.deletedAt == nil })).first
    }

    public func audioData(for recording: AudioRecording) throws -> Data {
        let assetID = recording.assetID
        guard let asset = try context.fetch(FetchDescriptor<Asset>(predicate: #Predicate { $0.id == assetID })).first,
              !asset.data.isEmpty
        else { throw StoreError.notFound("the audio for this recording") }
        return asset.data
    }

    public func timeline(for recording: AudioRecording) -> AudioTimeline {
        AudioTimeline(startedAt: recording.startedAt, duration: recording.duration, encodedMarks: recording.timeline)
    }

    /// Stores a finished recording. Throws before touching the store if the audio is empty.
    @discardableResult
    public func save(notebookID: UUID, audio: Data, title: String, timeline: AudioTimeline,
                     filename: String = "recording.m4a", uti: String = "public.mpeg-4-audio",
                     now: Date = .now) throws -> AudioRecording {
        guard !audio.isEmpty else { throw StoreError.invalid("The recording is empty, so nothing was saved.") }
        let asset = Asset(kind: .audio, data: audio, sha256: Hashing.sha256Hex(audio), filename: filename, uti: uti, now: now)
        context.insert(asset)
        markDirty(asset, fields: ["kind", "data", "byteCount", "sha256", "filename", "uti"], now: now)
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let recording = AudioRecording(notebookID: notebookID, assetID: asset.id,
                                       title: name.isEmpty ? "Recording" : name, startedAt: timeline.startedAt,
                                       duration: timeline.duration, timeline: timeline.encodedMarks, now: now)
        context.insert(recording)
        markDirty(recording, fields: ["notebookID", "assetID", "title", "startedAt", "duration", "timeline"], now: now)
        try context.save()
        return recording
    }

    public func rename(_ id: UUID, to title: String, now: Date = .now) throws {
        guard let recording = try recording(id: id) else { throw StoreError.notFound("the recording") }
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw StoreError.invalid("A recording needs a name.") }
        recording.title = name
        markDirty(recording, fields: ["title"], now: now)
        try context.save()
    }

    public func softDelete(_ id: UUID, now: Date = .now) throws {
        guard let recording = try recording(id: id) else { throw StoreError.notFound("the recording") }
        recording.deletedAt = now
        markDirty(recording, fields: ["deletedAt"], now: now)
        try context.save()
    }

    public func restore(_ id: UUID, now: Date = .now) throws {
        guard let recording = try context.fetch(FetchDescriptor<AudioRecording>(predicate: #Predicate { $0.id == id })).first
        else { throw StoreError.notFound("the recording") }
        recording.deletedAt = nil
        markDirty(recording, fields: ["deletedAt"], now: now)
        try context.save()
    }

    /// "Recording 1", "Recording 2", ... the first number not already used in this notebook (deleted ones count).
    public func nextTitle(in notebookID: UUID, prefix: String = "Recording") throws -> String {
        let all = try context.fetch(FetchDescriptor<AudioRecording>(predicate: #Predicate { $0.notebookID == notebookID }))
        let used = Set(all.map(\.title))
        var n = all.count + 1
        while used.contains("\(prefix) \(n)") { n += 1 }
        return "\(prefix) \(n)"
    }
}
