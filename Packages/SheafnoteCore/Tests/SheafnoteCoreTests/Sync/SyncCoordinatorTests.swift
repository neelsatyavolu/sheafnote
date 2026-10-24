import Foundation
import SwiftData
import Testing
@testable import SheafnoteCore

@MainActor
@Suite struct SyncCoordinatorTests {
    /// Two devices that have both synced one notebook with one inked page.
    private func twoDevicesWithOnePage() async throws -> (cloud: InMemoryCloud, a: Device, b: Device, notebook: UUID, page: UUID) {
        let cloud = InMemoryCloud()
        let a = try Device(cloud: cloud)
        let b = try Device(cloud: cloud)
        let nb = try a.fx.store.notebook("Shared")
        let page = try #require(try a.pages(of: nb.id).first)
        try a.fx.edit(page, strokes: [("a", 1)])
        await a.sync()
        await b.sync()
        return (cloud, a, b, nb.id, page.id)
    }

    @Test func firstSyncUploadsEverythingAndAnotherDeviceReceivesIt() async throws {
        let cloud = InMemoryCloud()
        let a = try Device(cloud: cloud)
        let b = try Device(cloud: cloud)
        let nb = try a.fx.store.notebook("Chemistry")
        await a.sync()
        #expect(a.coordinator.status == .idle)
        #expect(a.dirtyCount() == 0 && a.coordinator.lastSyncDate != nil)
        #expect(cloud.record(RecordKey(recordType: "SNNotebook", id: nb.id))?.string("title") == "Chemistry")
        await b.sync()
        #expect(b.notebook(nb.id)?.title == "Chemistry")
        #expect(try b.pages(of: nb.id).count == 1)
        #expect(b.dirtyCount() == 0)
    }

    @Test func secondSyncWithNoChangesSendsNothing() async throws {
        let (_, a, _, _, _) = try await twoDevicesWithOnePage()
        let before = a.transport.savesSent.count
        await a.sync()
        #expect(a.transport.savesSent.count == before)
    }

    @Test func concurrentOfflineInkEditsMergeAndConverge() async throws {
        let (_, a, b, _, pageID) = try await twoDevicesWithOnePage()
        a.transport.isOnline = false
        b.transport.isOnline = false
        try a.fx.edit(try a.page(pageID), strokes: [("a", 1), ("fromA", 2)])
        try b.fx.edit(try b.page(pageID), strokes: [("a", 1), ("fromB", 3)])
        await a.sync()
        #expect(a.coordinator.status == .offline)
        #expect(a.dirtyCount() == 1)
        a.transport.isOnline = true
        b.transport.isOnline = true
        await a.sync()
        await b.sync()      // conflict: merges and resends
        await a.sync()      // receives the merged version
        #expect(b.coordinator.lastReport.merged == 1)
        #expect(a.strokeIDs(of: pageID) == ["a", "fromA", "fromB"])
        #expect(b.strokeIDs(of: pageID) == ["a", "fromA", "fromB"])
        #expect(a.dirtyCount() == 0 && b.dirtyCount() == 0)
    }

    @Test func concurrentDeletionsOnTwoDevicesBothApply() async throws {
        let (_, a, b, _, pageID) = try await twoDevicesWithOnePage()
        try a.fx.edit(try a.page(pageID), strokes: [("a", 1), ("b", 2), ("c", 3)])
        await a.sync()
        await b.sync()
        try a.fx.edit(try a.page(pageID), strokes: [("b", 2), ("c", 3)])
        try b.fx.edit(try b.page(pageID), strokes: [("a", 1), ("c", 3)])
        await a.sync()
        await b.sync()
        await a.sync()
        #expect(a.strokeIDs(of: pageID) == ["c"] && b.strokeIDs(of: pageID) == ["c"])
    }

    @Test func deleteOnOneDeviceEditOnTheOtherKeepsTheEdit() async throws {
        let (_, a, b, _, pageID) = try await twoDevicesWithOnePage()
        try a.fx.edit(try a.page(pageID), strokes: [])                  // A erases a
        try b.fx.edit(try b.page(pageID), strokes: [("a2", 5)])         // B recolors a (a -> a2)
        await a.sync()
        await b.sync()
        await a.sync()
        #expect(a.strokeIDs(of: pageID) == ["a2"] && b.strokeIDs(of: pageID) == ["a2"])
    }

    @Test func identicalEditsOnBothDevicesDoNotDuplicate() async throws {
        let (_, a, b, _, pageID) = try await twoDevicesWithOnePage()
        try a.fx.edit(try a.page(pageID), strokes: [("a", 1), ("same", 2)])
        try b.fx.edit(try b.page(pageID), strokes: [("a", 1), ("same", 2)])
        await a.sync()
        await b.sync()
        await a.sync()
        #expect(a.strokeIDs(of: pageID) == ["a", "same"] && b.strokeIDs(of: pageID) == ["a", "same"])
        #expect(b.dirtyCount() == 0)
    }

    @Test func nonInkFieldsOnDifferentFieldsBothSurvive() async throws {
        let (_, a, b, nb, _) = try await twoDevicesWithOnePage()
        try a.library.rename(.notebook(nb), to: "Renamed on A")
        try b.library.setFavorite([.notebook(nb)], true)
        await a.sync()
        await b.sync()
        await a.sync()
        for d in [a, b] {
            #expect(d.notebook(nb)?.title == "Renamed on A" && d.notebook(nb)?.isFavorite == true)
        }
    }

    @Test func softDeletePropagatesAsTombstoneAndKeepsTheRow() async throws {
        let (_, a, b, nb, _) = try await twoDevicesWithOnePage()
        try a.library.softDelete([.notebook(nb)])
        await a.sync()
        await b.sync()
        let received = try #require(b.notebook(nb))
        #expect(received.deletedAt != nil)
        try b.library.restore([.notebook(nb)])
        await b.sync()
        await a.sync()
        #expect(a.notebook(nb)?.deletedAt == nil)
    }

    @Test func purgeDeletesTheCloudKitRecordOnlyAfterThirtyDays() async throws {
        let (cloud, a, b, nb, _) = try await twoDevicesWithOnePage()
        let key = RecordKey(recordType: "SNNotebook", id: nb)
        let deletedAt = Date.now
        try a.library.softDelete([.notebook(nb)], now: deletedAt)
        await a.sync()
        await b.sync()   // b now holds the tombstone in Recently Deleted
        #expect(try a.library.purgeExpired(now: deletedAt.addingTimeInterval(29 * day)) == 0)
        await a.sync()
        #expect(cloud.record(key) != nil)
        #expect(try a.library.purgeExpired(now: deletedAt.addingTimeInterval(31 * day)) > 0)
        #expect(a.coordinator.pendingDeletionCount > 0)
        await a.sync()
        #expect(cloud.record(key) == nil && a.coordinator.pendingDeletionCount == 0)
        await b.sync()   // removed for good on b too
        #expect(b.notebook(nb) == nil)
    }

    @Test func purgeQueuedWhileOfflineSurvivesRelaunch() async throws {
        let (cloud, a, _, nb, _) = try await twoDevicesWithOnePage()
        try a.library.softDelete([.notebook(nb)], now: .now.addingTimeInterval(-40 * day))
        await a.sync()
        a.transport.isOnline = false
        _ = try a.library.purgeExpired()
        await a.sync()
        let relaunched = SyncCoordinator(context: a.context, transport: a.transport, ink: JSONInkMerging(),
                                         persistence: a.persistence)
        #expect(relaunched.pendingDeletionCount > 0)
        a.transport.isOnline = true
        await relaunched.syncNow()
        #expect(cloud.record(RecordKey(recordType: "SNNotebook", id: nb)) == nil)
    }

    @Test func serverDeletionNeverRemovesALiveNotebook() async throws {
        let (cloud, a, b, nb, _) = try await twoDevicesWithOnePage()
        cloud.deleteZone()
        cloud.createZone()
        await b.sync()
        #expect(b.notebook(nb) != nil)
        #expect(try a.pages(of: nb).count == 1)
    }

    @Test func clearedICloudDataIsRepairedByReuploadingLocalData() async throws {
        let (cloud, a, _, nb, _) = try await twoDevicesWithOnePage()
        cloud.deleteZone()
        await a.sync()
        #expect(a.coordinator.status == .idle)
        #expect(cloud.record(RecordKey(recordType: "SNNotebook", id: nb)) != nil)
        #expect(a.notebook(nb) != nil)
    }

    @Test func signOutKeepsAllLocalDataAndEditsStayQueued() async throws {
        let (_, a, _, nb, pageID) = try await twoDevicesWithOnePage()
        a.transport.simulate(.signedOut)
        await a.sync()
        #expect(a.coordinator.status == .signedOut)
        try a.fx.edit(try a.page(pageID), strokes: [("a", 1), ("offline", 4)])
        await a.sync()
        #expect(a.notebook(nb) != nil && (a.strokeIDs(of: pageID)) == ["a", "offline"])
        #expect(a.dirtyCount() == 1)
        a.transport.simulate(.signedIn)
        try await Task.sleep(for: .milliseconds(100))
        #expect(a.coordinator.status == .idle && (a.dirtyCount()) == 0)
    }

    @Test func accountSwitchKeepsLocalDataAndWaitsForTheUsersChoice() async throws {
        let (_, a, _, nb, _) = try await twoDevicesWithOnePage()
        let other = InMemoryCloud()
        a.transport.attach(to: other)
        a.transport.simulate(.switched)
        try await Task.sleep(for: .milliseconds(50))
        #expect(a.coordinator.awaitingAccountDecision)
        await a.sync()
        #expect(other.records.isEmpty)                       // nothing uploaded without the answer
        #expect(a.notebook(nb) != nil)
        await a.coordinator.resolveAccountSwitch(upload: true)
        #expect(other.record(RecordKey(recordType: "SNNotebook", id: nb)) != nil)
        #expect(a.notebook(nb) != nil && !a.coordinator.awaitingAccountDecision)
    }

    @Test func decliningTheUploadAfterAccountSwitchGoesLocalOnlyAndDeletesNothing() async throws {
        let (_, a, _, nb, _) = try await twoDevicesWithOnePage()
        let other = InMemoryCloud()
        a.transport.attach(to: other)
        a.transport.simulate(.switched)
        try await Task.sleep(for: .milliseconds(50))
        await a.coordinator.resolveAccountSwitch(upload: false)
        #expect(a.coordinator.status == .localOnly && !a.coordinator.isEnabled)
        #expect(other.records.isEmpty && a.notebook(nb) != nil)
    }

    @Test func accountSwitchDropsQueuedDeletionsForTheOldAccount() async throws {
        let (_, a, _, nb, _) = try await twoDevicesWithOnePage()
        try a.library.softDelete([.notebook(nb)], now: .now.addingTimeInterval(-40 * day))
        _ = try a.library.purgeExpired()
        #expect(a.coordinator.pendingDeletionCount > 0)
        a.transport.simulate(.switched)
        try await Task.sleep(for: .milliseconds(50))
        #expect(a.coordinator.pendingDeletionCount == 0)
    }

    @Test func localOnlyModeSendsNothingAndKeepsEditsQueuedUntilReenabled() async throws {
        let cloud = InMemoryCloud()
        let a = try Device(cloud: cloud)
        await a.coordinator.setEnabled(false)
        #expect(a.coordinator.status == .localOnly)
        let nb = try a.fx.store.notebook("Private")
        await a.sync()
        #expect(a.transport.savesSent.isEmpty && cloud.records.isEmpty && !a.transport.started)
        #expect(a.dirtyCount() > 0)
        await a.coordinator.setEnabled(true)
        #expect(cloud.record(RecordKey(recordType: "SNNotebook", id: nb.id)) != nil && a.coordinator.status == .idle)
    }

    @Test func localOnlySettingSurvivesRelaunch() async throws {
        let cloud = InMemoryCloud()
        let a = try Device(cloud: cloud)
        await a.coordinator.setEnabled(false)
        let relaunched = SyncCoordinator(context: a.context, transport: a.transport, ink: JSONInkMerging(),
                                         persistence: a.persistence)
        #expect(!relaunched.isEnabled)
        await relaunched.start()
        #expect(relaunched.status == .localOnly)
    }

    @Test func quotaExceededIsReportedAndNothingIsLost() async throws {
        let cloud = InMemoryCloud()
        let a = try Device(cloud: cloud)
        let nb = try a.fx.store.notebook("Big")
        a.transport.quotaFull = true
        await a.sync()
        #expect(a.coordinator.status == .quotaExceeded)
        #expect(a.notebook(nb.id) != nil && (a.dirtyCount()) > 0)
        a.transport.quotaFull = false
        await a.sync()
        #expect(a.coordinator.status == .idle && (a.dirtyCount()) == 0)
    }

    @Test func recordFromANewerAppVersionIsNeverWrittenBack() async throws {
        let cloud = InMemoryCloud()
        let a = try Device(cloud: cloud)
        let id = UUID()
        _ = cloud.put(SyncRecord(key: RecordKey(recordType: "SNFolder", id: id), fields: [
            "name": .string("v2 folder"), "sortKey": .string("m"), "formatVersion": .int(2),
            "createdAt": .date(.now), "modifiedAt": .date(.now), "futureField": .string("x"),
        ]))
        await a.sync()
        let row = try #require(try a.context.fetch(FetchDescriptor<Folder>()).first)
        markDirty(row, fields: ["name"])
        await a.sync()
        #expect(a.transport.savesSent.allSatisfy { $0.id != id })
        #expect(cloud.record(RecordKey(recordType: "SNFolder", id: id))?.string("name") == "v2 folder")
    }

    @Test func echoOfOurOwnSaveDoesNotCreateRecoveredSnapshots() async throws {
        let (_, a, _, _, pageID) = try await twoDevicesWithOnePage()
        try a.fx.edit(try a.page(pageID), strokes: [("a", 1), ("b", 2)])
        await a.sync()
        try a.fx.edit(try a.page(pageID), strokes: [("a", 1), ("b", 2), ("c", 3)])   // edited after the send, before the echo
        await a.sync()
        #expect(try a.context.fetch(FetchDescriptor<PageRevision>()).isEmpty)
        #expect(a.strokeIDs(of: pageID) == ["a", "b", "c"])
    }

    @Test func corruptInkFromAnotherDeviceKeepsBothVersions() async throws {
        let (cloud, a, _, _, pageID) = try await twoDevicesWithOnePage()
        let key = RecordKey(recordType: "SNPage", id: pageID)
        var server = try #require(cloud.record(key))
        server.fields["inkData"] = .bytes(Data("garbage".utf8))
        server.fields["strokeIDs"] = .strings(["zzz"])
        server.fields["inkHash"] = .string("other")
        server.fields["modifiedAt"] = .date(.now.addingTimeInterval(60))
        _ = cloud.put(server)
        try a.fx.edit(try a.page(pageID), strokes: [("a", 1), ("mine", 9)])
        await a.sync()
        #expect(a.strokeIDs(of: pageID) == ["a", "mine"])
        let recovered = try a.context.fetch(FetchDescriptor<PageRevision>())
        #expect(recovered.contains { $0.inkData == Data("garbage".utf8) && $0.reasonValue == .conflict })
        #expect(a.coordinator.lastReport.keptBothVersions == 1)
    }

    @Test func concurrentSyncCallsAreCoalesced() async throws {
        let cloud = InMemoryCloud()
        let a = try Device(cloud: cloud)
        try a.fx.store.notebook("One")
        async let first: Void = a.sync()
        async let second: Void = a.sync()
        _ = await (first, second)
        #expect(a.dirtyCount() == 0)
    }

    @Test func childRecordsArrivingBeforeTheirParentStillShowUp() async throws {
        let cloud = InMemoryCloud()
        let b = try Device(cloud: cloud)
        let nbID = UUID()
        _ = cloud.put(SyncRecord(key: RecordKey(recordType: "SNPage", id: UUID()), fields: [
            "notebookID": .string(nbID.uuidString), "sortKey": .string("m"), "widthPts": .double(10), "heightPts": .double(10),
            "createdAt": .date(.now), "modifiedAt": .date(.now), "formatVersion": .int(1),
        ]))
        await b.sync()
        #expect(try b.context.fetch(FetchDescriptor<Page>()).count == 1)
        #expect(b.dirtyCount() == 0)
    }
}
