import Foundation
import SwiftData

public enum RevisionReason: String, Codable, CaseIterable, Sendable { case conflict, beforeDelete, beforeClear, restore }

/// LOCAL ONLY (the Recovered area). Not syncable.
@Model
public final class PageRevision {
    @Attribute(.unique) public var id: UUID
    public var pageID: UUID
    public var notebookID: UUID
    public var reason: String
    public var createdAt: Date
    public var expiresAt: Date
    @Attribute(.externalStorage) public var inkData: Data?
    public var strokeIDs: [String]
    /// JSON `[ElementValue]`
    @Attribute(.externalStorage) public var elements: Data
    public var note: String?

    public init(id: UUID = UUID(), pageID: UUID, notebookID: UUID, reason: RevisionReason, createdAt: Date = .now,
                inkData: Data?, strokeIDs: [String], elements: Data, note: String? = nil) {
        self.id = id
        self.pageID = pageID
        self.notebookID = notebookID
        self.reason = reason.rawValue
        self.createdAt = createdAt
        self.expiresAt = createdAt.addingTimeInterval(Retention.seconds)
        self.inkData = inkData
        self.strokeIDs = strokeIDs
        self.elements = elements
        self.note = note
    }

    public var reasonValue: RevisionReason { RevisionReason(rawValue: reason) ?? .conflict }
}

public enum Retention {
    public static let days = 30
    public static let seconds: TimeInterval = TimeInterval(days) * 86_400
}
