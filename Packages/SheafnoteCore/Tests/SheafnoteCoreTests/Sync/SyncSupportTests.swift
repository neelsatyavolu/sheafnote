import Foundation
import SwiftData
import Testing
@testable import SheafnoteCore

@Suite struct PurgePolicyTests {
    private let now = Date(timeIntervalSinceReferenceDate: 10_000_000)

    @Test func tombstonesExpireOnlyAfterThirtyDays() {
        #expect(PurgePolicy.retention == 30 * 86_400)
        #expect(!PurgePolicy.isExpired(deletedAt: nil, now: now))
        #expect(!PurgePolicy.isExpired(deletedAt: now.addingTimeInterval(-29 * 86_400), now: now))
        #expect(!PurgePolicy.isExpired(deletedAt: now.addingTimeInterval(-30 * 86_400), now: now))
        #expect(PurgePolicy.isExpired(deletedAt: now.addingTimeInterval(-30 * 86_400 - 1), now: now))
    }

    @Test func queueingDeduplicatesAndKeepsOrder() {
        let a = UUID(), b = UUID()
        let first = PurgePolicy.queueDeletions(existing: [], purged: [PurgedRecord(recordType: "SNPage", id: a)])
        let second = PurgePolicy.queueDeletions(existing: first, purged: [
            PurgedRecord(recordType: "SNPage", id: a), PurgedRecord(recordType: "SNNotebook", id: b),
        ])
        #expect(second == [RecordKey(recordType: "SNPage", id: a), RecordKey(recordType: "SNNotebook", id: b)])
    }

    @Test func recreatedRowsAreNotDeletedFromTheServer() {
        let a = RecordKey(recordType: "SNPage", id: UUID()), b = RecordKey(recordType: "SNPage", id: UUID())
        #expect(PurgePolicy.filterRecreated([a, b], existing: [a]) == [b])
    }
}

@Suite struct SyncPersistenceTests {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "sheafnote-sync-\(UUID().uuidString)/settings.json")
    }

    @Test func missingFileGivesDefaults() throws {
        let state = try FileSyncPersistence(url: tempURL()).load()
        #expect(state.isEnabled && state.needsFullUpload && state.pendingDeletions.isEmpty && state.lastSyncDate == nil)
    }

    @Test func stateRoundTripsThroughTheFile() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = FileSyncPersistence(url: url)
        var state = SyncPersistedState()
        state.isEnabled = false
        state.needsFullUpload = false
        state.awaitingAccountDecision = true
        state.lastSyncDate = Date(timeIntervalSinceReferenceDate: 1234)
        state.pendingDeletions = [RecordKey(recordType: "SNPage", id: UUID())]
        try store.save(state)
        #expect(try FileSyncPersistence(url: url).load() == state)
    }

    @Test func corruptFileThrowsInsteadOfSilentlyResetting() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{not json".utf8).write(to: url)
        #expect(throws: (any Error).self) { try FileSyncPersistence(url: url).load() }
    }

    @MainActor @Test func coordinatorSurfacesAnUnreadableSettingsFile() throws {
        final class Broken: SyncPersistence {
            func load() throws -> SyncPersistedState { throw CocoaError(.fileReadCorruptFile) }
            func save(_ state: SyncPersistedState) throws {}
        }
        let f = try SyncFixture()
        let coordinator = SyncCoordinator(context: f.context, transport: InMemoryTransport(cloud: InMemoryCloud()),
                                          ink: JSONInkMerging(), persistence: Broken())
        if case .error(let message) = coordinator.status { #expect(message.contains("could not be read")) } else {
            Issue.record("expected an error status")
        }
    }

    @MainActor @Test func coordinatorSurfacesAFailedSettingsSave() async throws {
        let f = try SyncFixture()
        let persistence = InMemorySyncPersistence()
        persistence.saveError = CocoaError(.fileWriteOutOfSpace)
        let coordinator = SyncCoordinator(context: f.context, transport: InMemoryTransport(cloud: InMemoryCloud()),
                                          ink: JSONInkMerging(), persistence: persistence)
        coordinator.recordPurged([PurgedRecord(recordType: "SNPage", id: UUID())])
        if case .error(let message) = coordinator.status { #expect(message.contains("could not be saved")) } else {
            Issue.record("expected an error status")
        }
    }
}

@MainActor
@Suite struct BatchingAndFailureTests {
    @Test func batchesSplitByCountAndPayload() {
        func save(_ bytes: Int) -> OutgoingChange {
            .save(SyncRecord(key: RecordKey(recordType: "SNAsset", id: UUID()), fields: ["data": .bytes(Data(count: bytes))]))
        }
        let many = (0..<120).map { _ in save(10) }
        #expect(SyncCoordinator.batches(many).map(\.count) == [50, 50, 20])
        let heavy = [save(15_000_000), save(15_000_000), save(1)]
        #expect(SyncCoordinator.batches(heavy).map(\.count) == [1, 2])
        #expect(SyncCoordinator.batches([]).isEmpty)
    }

    @Test func everyFailureHasAUserFriendlyMessage() {
        let all: [SyncFailure] = [.offline, .quotaExceeded, .notAuthenticated, .zoneNotFound, .rateLimited(retryAfter: 3),
                                  .other("Something specific.")]
        #expect(all.allSatisfy { !$0.userMessage.isEmpty })
        #expect(SyncFailure.other("Something specific.").userMessage == "Something specific.")
    }

    @Test func recoveredAreaListsRestoresAndDeletesWithoutOverwriting() throws {
        let f = try SyncFixture()
        let page = try f.syncedPage(strokes: [("a", 1), ("b", 2)])
        let revisions = RevisionStore(context: f.context)
        let rev = try revisions.snapshot(page: page, reason: .conflict, note: "theirs")
        let area = RecoveredArea(context: f.context)
        let items = try area.items()
        #expect(items.count == 1 && items[0].strokeCount == 2 && items[0].pageStillExists && items[0].note == "theirs")
        let restored = try area.restore(rev.id)
        #expect(restored.id != page.id && restored.strokeIDs == ["a", "b"] && page.strokeIDs == ["a", "b"])
        try area.delete(rev.id)
        #expect(try area.items().isEmpty)
        #expect(throws: StoreError.self) { try area.restore(rev.id) }
    }

    @Test func recoveredAreaHidesAndPurgesExpiredVersions() throws {
        let f = try SyncFixture()
        let page = try f.syncedPage(strokes: [("a", 1)])
        try RevisionStore(context: f.context).snapshot(page: page, reason: .conflict, now: .now.addingTimeInterval(-31 * 86_400))
        let area = RecoveredArea(context: f.context)
        #expect(try area.items().isEmpty)
        #expect(try area.purgeExpired() == 1)
    }
}
