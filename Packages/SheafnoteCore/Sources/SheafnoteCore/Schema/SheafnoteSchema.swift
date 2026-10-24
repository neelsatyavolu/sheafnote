import Foundation
import SwiftData

public enum SheafnoteSchemaV1: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }
    public static var models: [any PersistentModel.Type] {
        [Folder.self, Notebook.self, Page.self, PageElement.self, Asset.self, OutlineEntry.self,
         Bookmark.self, AudioRecording.self, Flashcard.self, StudyState.self, SavedElement.self,
         AppSetting.self, PageRevision.self]
    }
}

public enum SheafnoteMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] { [SheafnoteSchemaV1.self] }
    public static var stages: [MigrationStage] { [] }
}

public enum SheafnoteStore {
    public static let fileName = "Sheafnote.store"

    /// Local, NOT CloudKit-backed store in Application Support (or in memory for tests).
    public static func makeContainer(inMemory: Bool = false, url: URL? = nil) throws -> ModelContainer {
        let schema = Schema(versionedSchema: SheafnoteSchemaV1.self)
        let config: ModelConfiguration
        if inMemory {
            config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        } else {
            let storeURL = try url ?? defaultURL()
            config = ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
        }
        return try ModelContainer(for: schema, migrationPlan: SheafnoteMigrationPlan.self, configurations: [config])
    }

    public static func defaultURL() throws -> URL {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                               appropriateFor: nil, create: true)
        return base.appending(path: fileName)
    }
}
