import PencilKit
import SwiftData
import Testing
import SheafnoteCore
@testable import Sheafnote

/// Two simulated devices with real stores and real PencilKit drawings, synced through `InMemoryCloud`.
@MainActor
@Suite struct SyncEndToEndTests {
    @MainActor private struct Device {
        let services: AppServices
        let transport: InMemoryTransport
        let coordinator: SyncCoordinator

        init(cloud: InMemoryCloud) throws {
            services = try AppServices.inMemory()
            transport = InMemoryTransport(cloud: cloud)
            coordinator = SyncCoordinator(context: services.context, transport: transport, ink: PageInkMerger(),
                                          persistence: InMemorySyncPersistence())
        }

        func page(_ id: UUID) throws -> Page { try #require(services.pages.page(id: id)) }

        func write(_ items: [(String, CGFloat, Double)], to pageID: UUID) throws {
            let strokes = items.map { item -> PKStroke in
                let points = (0..<2).map { i in
                    PKStrokePoint(location: CGPoint(x: item.1 + CGFloat(i), y: 3), timeOffset: Double(i) * 0.01,
                                  size: CGSize(width: 2, height: 2), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
                }
                let path = PKStrokePath(controlPoints: points, creationDate: Date(timeIntervalSinceReferenceDate: item.2))
                return PKStroke(ink: PKInk(.pen, color: .black), path: path)
            }
            try services.pages.saveInk(pageID: pageID, drawingData: PKDrawing(strokes: strokes).dataRepresentation(),
                                       strokeIDs: items.map { StrokeID(rawValue: $0.0) })
        }

        func strokeXs(of pageID: UUID) throws -> [CGFloat] {
            let data = try #require(try page(pageID).inkData)
            return try PKDrawing(data: data).strokes.map { $0.path.first?.location.x ?? -1 }
        }
    }

    @Test func offlineInkOnTwoDevicesMergesIntoOneDrawing() async throws {
        let cloud = InMemoryCloud()
        let a = try Device(cloud: cloud), b = try Device(cloud: cloud)
        let nb = try a.services.library.createNotebook(title: "Lecture", kind: .paged, cover: .default, template: .blank,
                                                       paperSize: .a4, orientation: .portrait, paperColor: .white, in: nil)
        let pageID = try #require(try a.services.pages.orderedPages(of: nb.id).first).id
        try a.write([("base", 0, 1)], to: pageID)
        await a.coordinator.syncNow()
        await b.coordinator.syncNow()
        #expect(try b.strokeXs(of: pageID) == [0])

        a.transport.isOnline = false
        b.transport.isOnline = false
        try a.write([("base", 0, 1), ("fromA", 100, 2)], to: pageID)
        try b.write([("base", 0, 1), ("fromB", 200, 3)], to: pageID)
        a.transport.isOnline = true
        b.transport.isOnline = true
        await a.coordinator.syncNow()
        await b.coordinator.syncNow()
        await a.coordinator.syncNow()

        #expect(try a.strokeXs(of: pageID) == [0, 100, 200])
        #expect(try b.strokeXs(of: pageID) == [0, 100, 200])
        #expect(try a.page(pageID).strokeIDs == ["base", "fromA", "fromB"])
        #expect(try RecordMapper.dirtyKeys(in: a.services.context).isEmpty && RecordMapper.dirtyKeys(in: b.services.context).isEmpty)
    }

    @Test func unreadableServerInkNeverCostsTheLocalDrawing() async throws {
        let cloud = InMemoryCloud()
        let a = try Device(cloud: cloud)
        let nb = try a.services.library.createNotebook(title: "N", kind: .paged, cover: .default, template: .blank,
                                                       paperSize: .a4, orientation: .portrait, paperColor: .white, in: nil)
        let pageID = try #require(try a.services.pages.orderedPages(of: nb.id).first).id
        try a.write([("one", 0, 1)], to: pageID)
        await a.coordinator.syncNow()
        var server = try #require(cloud.record(RecordKey(recordType: "SNPage", id: pageID)))
        server.fields["inkData"] = .bytes(Data("not a drawing".utf8))
        server.fields["strokeIDs"] = .strings(["junk"])
        server.fields["inkHash"] = .string("junk")
        _ = cloud.put(server)
        try a.write([("one", 0, 1), ("two", 50, 2)], to: pageID)
        await a.coordinator.syncNow()
        #expect(try a.strokeXs(of: pageID) == [0, 50])
        let recovered = try RecoveredArea(context: a.services.context).items()
        #expect(recovered.contains { $0.reason == .conflict })
    }
}
