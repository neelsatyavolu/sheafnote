import Foundation
import SwiftData
import Testing
@testable import SheafnoteCore

/// One simulated device: its own store, transport and coordinator.
@MainActor
struct Device {
    let fx: SyncFixture
    let transport: InMemoryTransport
    let persistence: InMemorySyncPersistence
    let coordinator: SyncCoordinator
    var context: ModelContext { fx.context }
    var library: LibraryStore { fx.store.library }

    init(cloud: InMemoryCloud, state: SyncPersistedState = SyncPersistedState()) throws {
        fx = try SyncFixture()
        transport = InMemoryTransport(cloud: cloud)
        persistence = InMemorySyncPersistence(state: state)
        coordinator = SyncCoordinator(context: fx.context, transport: transport, ink: JSONInkMerging(),
                                      persistence: persistence)
        let coordinator = coordinator
        fx.store.library.onPurge = { coordinator.recordPurged($0) }
    }

    func sync() async { await coordinator.syncNow() }

    func pages(of notebook: UUID) throws -> [Page] { try fx.store.pages.orderedPages(of: notebook) }

    func page(_ id: UUID) throws -> Page {
        try #require(try context.fetch(FetchDescriptor<Page>()).first { $0.id == id })
    }

    func notebook(_ id: UUID) -> Notebook? { try? context.fetch(FetchDescriptor<Notebook>()).first { $0.id == id } }

    func dirtyCount() -> Int { (try? RecordMapper.dirtyKeys(in: context).count) ?? -1 }

    func strokeIDs(of page: UUID) -> [String] { (try? self.page(page).strokeIDs) ?? ["<missing>"] }
}
