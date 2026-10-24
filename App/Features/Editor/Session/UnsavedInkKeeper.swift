import Foundation
import OSLog

/// Keeps a notebook session alive after its editor closed while some ink could not be written (disk full, store
/// error). The strokes exist only in the session, so letting it go would lose them. The keeper retries until the
/// write succeeds, then lets the session go.
@MainActor
final class UnsavedInkKeeper {
    static let shared = UnsavedInkKeeper(retryInterval: .seconds(5))
    private static let log = Logger(subsystem: "co.xanom.sheafnote", category: "ink")

    private let retryInterval: Duration
    private var held: [ObjectIdentifier: NotebookSession] = [:]
    private var task: Task<Void, Never>?

    init(retryInterval: Duration) { self.retryInterval = retryInterval }

    var heldCount: Int { held.count }

    /// Flushes the session; if that fails, holds on to it and keeps retrying. Returns true when everything was saved.
    @discardableResult
    func settle(_ session: NotebookSession) -> Bool {
        if session.flushAll() { return true }
        Self.log.error("Ink could not be saved on close; keeping the notebook session until it can be")
        held[ObjectIdentifier(session)] = session
        startRetrying()
        return false
    }

    private func startRetrying() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while let self, !self.held.isEmpty {
                try? await Task.sleep(for: self.retryInterval)
                if Task.isCancelled { break }
                self.retryHeld()
            }
            self?.task = nil
        }
    }

    /// Runs one retry pass (the loop calls this; tests call it directly).
    func retryHeld() {
        for (key, session) in held where session.flushAll() { held[key] = nil }
    }
}
