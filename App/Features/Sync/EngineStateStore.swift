import CloudKit
import Foundation

/// Persists the `CKSyncEngine` state serialization (change tokens, pending list) as JSON, written atomically.
/// Lives in `Application Support/SheafnoteSync/state.json`.
struct EngineStateStore: Sendable {
    struct Persisted: Codable {
        var serialization: CKSyncEngine.State.Serialization?
        var zoneCreated = false
    }

    let url: URL

    static func defaultURL() throws -> URL {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                               appropriateFor: nil, create: true)
        return base.appending(path: "SheafnoteSync", directoryHint: .isDirectory).appending(path: "state.json")
    }

    func load() throws -> Persisted {
        guard FileManager.default.fileExists(atPath: url.path) else { return Persisted() }
        return try JSONDecoder().decode(Persisted.self, from: Data(contentsOf: url))
    }

    func save(_ state: Persisted) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(state).write(to: url, options: .atomic)
    }
}
