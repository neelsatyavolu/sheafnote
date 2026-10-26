import Foundation
import SwiftData

/// Key paths written against the concrete model, for fetches in generic code. In optimized builds SwiftData cannot
/// resolve a key path formed generically (`\T.id` with `T: SyncCodable`) and traps in `keyPathToString`.
struct SyncKeyPaths<T: PersistentModel> {
    let id: any KeyPath<T, UUID> & Sendable
    let syncDirty: any KeyPath<T, Bool> & Sendable
    let formatVersion: any KeyPath<T, Int> & Sendable
}

extension Folder { static var syncKeyPaths: SyncKeyPaths<Folder> { .init(id: \.id, syncDirty: \.syncDirty, formatVersion: \.formatVersion) } }
extension Notebook { static var syncKeyPaths: SyncKeyPaths<Notebook> { .init(id: \.id, syncDirty: \.syncDirty, formatVersion: \.formatVersion) } }
extension Page { static var syncKeyPaths: SyncKeyPaths<Page> { .init(id: \.id, syncDirty: \.syncDirty, formatVersion: \.formatVersion) } }
extension PageElement { static var syncKeyPaths: SyncKeyPaths<PageElement> { .init(id: \.id, syncDirty: \.syncDirty, formatVersion: \.formatVersion) } }
extension Asset { static var syncKeyPaths: SyncKeyPaths<Asset> { .init(id: \.id, syncDirty: \.syncDirty, formatVersion: \.formatVersion) } }
extension OutlineEntry { static var syncKeyPaths: SyncKeyPaths<OutlineEntry> { .init(id: \.id, syncDirty: \.syncDirty, formatVersion: \.formatVersion) } }
extension Bookmark { static var syncKeyPaths: SyncKeyPaths<Bookmark> { .init(id: \.id, syncDirty: \.syncDirty, formatVersion: \.formatVersion) } }
extension AudioRecording { static var syncKeyPaths: SyncKeyPaths<AudioRecording> { .init(id: \.id, syncDirty: \.syncDirty, formatVersion: \.formatVersion) } }
extension Flashcard { static var syncKeyPaths: SyncKeyPaths<Flashcard> { .init(id: \.id, syncDirty: \.syncDirty, formatVersion: \.formatVersion) } }
extension StudyState { static var syncKeyPaths: SyncKeyPaths<StudyState> { .init(id: \.id, syncDirty: \.syncDirty, formatVersion: \.formatVersion) } }
extension SavedElement { static var syncKeyPaths: SyncKeyPaths<SavedElement> { .init(id: \.id, syncDirty: \.syncDirty, formatVersion: \.formatVersion) } }
extension AppSetting { static var syncKeyPaths: SyncKeyPaths<AppSetting> { .init(id: \.id, syncDirty: \.syncDirty, formatVersion: \.formatVersion) } }
