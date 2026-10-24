import Foundation
import Observation
import SwiftData
import SheafnoteCore

/// Everything features need from the app: the local store and the services built on it.
@MainActor @Observable
final class AppServices {
    let container: ModelContainer              // local SwiftData store (not CloudKit-backed)
    let library: LibraryStore                  // folders/notebooks CRUD, soft delete, restore, purge
    let pages: PageStore                       // ink data + elements persistence
    let revisions: RevisionStore               // Recovered area (PageRevision)
    let elementLibrary: any ElementLibrary
    let recognizer: any HandwritingRecognizing
    let settings: AppSettingsStore             // synced AppSetting + local UserDefaults
    var pageRenderer: any PageRenderer         // placeholder until Editor registers the real one
    var syncStatus: SyncStatusModel            // observable; Sync updates, Settings shows

    init(container: ModelContainer, defaults: UserDefaults = .standard,
         recognizer: any HandwritingRecognizing = VisionHandwritingRecognizer()) {
        let context = container.mainContext
        let revisions = RevisionStore(context: context)
        let library = LibraryStore(context: context)
        let pages = PageStore(context: context, revisions: revisions)
        self.container = container
        self.library = library
        self.pages = pages
        self.revisions = revisions
        self.recognizer = recognizer
        self.settings = AppSettingsStore(context: context, defaults: defaults)
        self.elementLibrary = ElementLibraryStore(store: SavedElementStore(context: context))
        self.pageRenderer = PlaceholderPageRenderer(library: library, pages: pages)
        self.syncStatus = SyncStatusModel()
    }

    var context: ModelContext { container.mainContext }

    /// Production services over the on-disk store. Throws if the store cannot be opened; the caller must show
    /// the error and must NOT delete or reset the store.
    static func live() throws -> AppServices {
        AppServices(container: try SheafnoteStore.makeContainer())
    }

    /// In-memory services for previews, tests and UI-test mode.
    static func inMemory(defaults: UserDefaults? = nil) throws -> AppServices {
        let suite = defaults ?? UserDefaults(suiteName: "co.xanom.sheafnote.memory.\(UUID().uuidString)") ?? .standard
        return AppServices(container: try SheafnoteStore.makeContainer(inMemory: true), defaults: suite)
    }
}
