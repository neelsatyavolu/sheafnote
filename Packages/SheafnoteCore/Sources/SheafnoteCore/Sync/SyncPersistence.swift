import Foundation

/// Small device-local sync state that must survive a relaunch.
public struct SyncPersistedState: Codable, Equatable, Sendable {
    /// False means local-only mode: the engine is not started and nothing leaves the device.
    public var isEnabled = true
    /// Records purged locally whose CloudKit counterparts still have to be deleted.
    public var pendingDeletions: [RecordKey] = []
    public var lastSyncDate: Date?
    /// True until every local row has been queued for upload to the current account.
    public var needsFullUpload = true
    /// The iCloud account changed and the user has not yet chosen whether to upload this device's notebooks.
    public var awaitingAccountDecision = false

    public init() {}
}

public protocol SyncPersistence: AnyObject {
    func load() throws -> SyncPersistedState
    func save(_ state: SyncPersistedState) throws
}

public final class InMemorySyncPersistence: SyncPersistence {
    public var state: SyncPersistedState
    public var saveError: Error?

    public init(state: SyncPersistedState = SyncPersistedState()) { self.state = state }

    public func load() throws -> SyncPersistedState { state }

    public func save(_ new: SyncPersistedState) throws {
        if let saveError { throw saveError }
        state = new
    }
}

/// JSON file in Application Support/SheafnoteSync, written atomically.
public final class FileSyncPersistence: SyncPersistence {
    public let url: URL

    public init(url: URL) { self.url = url }

    public static func defaultURL() throws -> URL {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                               appropriateFor: nil, create: true)
        return base.appending(path: "SheafnoteSync", directoryHint: .isDirectory).appending(path: "settings.json")
    }

    public func load() throws -> SyncPersistedState {
        guard FileManager.default.fileExists(atPath: url.path) else { return SyncPersistedState() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(SyncPersistedState.self, from: Data(contentsOf: url))
    }

    public func save(_ state: SyncPersistedState) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(state).write(to: url, options: .atomic)
    }
}
