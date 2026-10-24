import Foundation
import SwiftData
import Testing
@testable import SheafnoteCore

@MainActor
@Suite struct SettingsStoreTests {
    struct Prefs: Codable, Equatable { var a: Int; var b: String }

    @Test func syncedRoundTripAndSingleRow() throws {
        let f = try StoreFixture()
        let s = AppSettingsStore(context: f.context, defaults: UserDefaults(suiteName: "t1-\(UUID())")!)
        #expect(s.synced("k", as: Prefs.self) == nil)
        try s.setSynced(Prefs(a: 1, b: "x"), for: "k")
        try s.setSynced(Prefs(a: 2, b: "y"), for: "k")
        #expect(s.synced("k", as: Prefs.self) == Prefs(a: 2, b: "y"))
        #expect(try f.context.fetch(FetchDescriptor<AppSetting>()).count == 1)
        #expect(try f.context.fetch(FetchDescriptor<AppSetting>())[0].id == AppSettingsStore.settingID(for: "k"))
    }

    @Test func settingIDIsStableAndDistinct() {
        #expect(AppSettingsStore.settingID(for: "a") == AppSettingsStore.settingID(for: "a"))
        #expect(AppSettingsStore.settingID(for: "a") != AppSettingsStore.settingID(for: "b"))
    }

    @Test func localRoundTrip() throws {
        let f = try StoreFixture()
        let s = AppSettingsStore(context: f.context, defaults: UserDefaults(suiteName: "t2-\(UUID())")!)
        s.setLocal(Prefs(a: 3, b: "z"), for: "loc")
        #expect(s.local("loc", as: Prefs.self) == Prefs(a: 3, b: "z"))
        s.removeLocal("loc")
        #expect(s.local("loc", as: Prefs.self) == nil)
    }
}

@MainActor
@Suite struct SavedElementStoreTests {
    @Test func saveRenameDelete() throws {
        let f = try StoreFixture()
        let store = SavedElementStore(context: f.context)
        let el = ElementValue(pageID: UUID(), kind: .sticker, frame: CGRect(x: 0, y: 0, width: 5, height: 5))
        let saved = try store.save(name: "Star", category: "Shapes", size: CGSize(width: 5, height: 5),
                                   inkData: Data([1]), elements: [el], thumbnail: Data([2]))
        #expect(try store.all().count == 1)
        #expect(try store.all()[0].elements == [el])
        try store.rename(id: saved.id, to: "Big star")
        #expect(try store.all()[0].name == "Big star")
        try store.delete(id: saved.id)
        #expect(try store.all().isEmpty)
        #expect(throws: StoreError.self) { try store.rename(id: UUID(), to: "x") }
    }
}

@MainActor
@Suite struct LibraryListingTests {
    func world() throws -> (StoreFixture, [Folder], [Notebook]) {
        let f = try StoreFixture()
        let t = Date(timeIntervalSince1970: 1000)
        let zeta = try f.notebook("zeta", now: t)
        let alpha = try f.notebook("Alpha", now: t + 10)
        let item10 = try f.notebook("Note 10", now: t + 20)
        let item2 = try f.notebook("Note 2", now: t + 30)
        _ = (zeta, alpha, item10, item2)
        _ = try f.library.createFolder(name: "Folder", in: nil, now: t + 5)
        return (f, try f.library.allFolders(), try f.library.allNotebooks())
    }

    @Test func foldersFirstThenNotebooksSortedByName() throws {
        let (f, fs, ns) = try world()
        defer { withExtendedLifetime(f) {} }
        let e = LibraryListing.entries(scope: .documents, folders: fs, notebooks: ns, sort: .init(field: .name, ascending: true))
        #expect(e.map(\.title) == ["Folder", "Alpha", "Note 2", "Note 10", "zeta"])   // natural order, case-insensitive
    }

    @Test func sortByCreatedAndModified() throws {
        let (f, fs, ns) = try world()
        defer { withExtendedLifetime(f) {} }
        let created = LibraryListing.entries(scope: .documents, folders: [], notebooks: ns, sort: .init(field: .created, ascending: true))
        #expect(created.map(\.title) == ["zeta", "Alpha", "Note 10", "Note 2"])
        let modified = LibraryListing.entries(scope: .documents, folders: fs, notebooks: ns, sort: .init(field: .modified, ascending: false))
        #expect(modified.dropFirst().map(\.title) == ["Note 2", "Note 10", "Alpha", "zeta"])
    }

    @Test func scopesFilter() throws {
        let (f, _, _) = try world()
        let folder = try f.library.createFolder(name: "Sub", in: nil)
        let inside = try f.notebook("Inside", in: folder.id)
        try f.library.setFavorite([.notebook(inside.id)], true)
        let fs = try f.library.allFolders(), ns = try f.library.allNotebooks()
        let sort = LibrarySort()
        #expect(LibraryListing.entries(scope: .folder(folder.id), folders: fs, notebooks: ns, sort: sort).map(\.title) == ["Inside"])
        #expect(LibraryListing.entries(scope: .favorites, folders: fs, notebooks: ns, sort: sort).map(\.title) == ["Inside"])
        #expect(!LibraryListing.entries(scope: .documents, folders: fs, notebooks: ns, sort: sort).map(\.title).contains("Inside"))
    }

    @Test func trashShowsOnlyTopLevelAndNewestFirst() throws {
        let f = try StoreFixture()
        let folder = try f.library.createFolder(name: "F", in: nil)
        let inside = try f.notebook("Inside", in: folder.id)
        let lone = try f.notebook("Lone")
        try f.library.softDelete([.notebook(lone.id)], now: Date(timeIntervalSince1970: 100))
        try f.library.softDelete([.folder(folder.id)], now: Date(timeIntervalSince1970: 200))
        let trash = LibraryListing.entries(scope: .recentlyDeleted, folders: try f.library.allFolders(),
                                           notebooks: try f.library.allNotebooks(), sort: .init())
        #expect(trash.map(\.title) == ["F", "Lone"])
        #expect(!trash.contains { $0.id == inside.id })
    }

    @Test func trashShowsEarlierDeletedChildOfLaterDeletedFolder() throws {
        let f = try StoreFixture()
        let folder = try f.library.createFolder(name: "F", in: nil)
        let child = try f.notebook("Child", in: folder.id)
        try f.library.softDelete([.notebook(child.id)], now: Date(timeIntervalSince1970: 100))
        try f.library.softDelete([.folder(folder.id)], now: Date(timeIntervalSince1970: 200))
        let trash = LibraryListing.trash(folders: try f.library.allFolders(), notebooks: try f.library.allNotebooks())
        #expect(Set(trash.map(\.title)) == ["F", "Child"])
    }

    @Test func searchMatchesTitlesIgnoringCaseAndDiacritics() throws {
        let f = try StoreFixture()
        _ = try f.notebook("Résumé drafts")
        _ = try f.notebook("Other")
        let hidden = try f.notebook("resume hidden")
        try f.library.softDelete([.notebook(hidden.id)])
        let hits = LibraryListing.search("RESUME", folders: [], notebooks: try f.library.allNotebooks())
        #expect(hits.map(\.title) == ["Résumé drafts"])
        #expect(LibraryListing.search("  ", folders: [], notebooks: try f.library.allNotebooks()).isEmpty)
    }

    @Test func daysRemaining() {
        let t = Date(timeIntervalSince1970: 0)
        #expect(LibraryListing.daysRemaining(deletedAt: t, now: t) == 30)
        #expect(LibraryListing.daysRemaining(deletedAt: t, now: t + 29.5 * day) == 1)
        #expect(LibraryListing.daysRemaining(deletedAt: t, now: t + 40 * day) == 0)
    }

    @Test func pathAndChildCount() throws {
        let f = try StoreFixture()
        let a = try f.library.createFolder(name: "A", in: nil)
        let b = try f.library.createFolder(name: "B", in: a.id)
        _ = try f.notebook("x", in: a.id)
        let fs = try f.library.allFolders(), ns = try f.library.allNotebooks()
        #expect(LibraryListing.path(to: b.id, folders: fs).map(\.name) == ["A", "B"])
        #expect(LibraryListing.childCount(of: a.id, folders: fs, notebooks: ns) == 2)
    }
}

@MainActor
@Suite struct SchemaTests {
    @Test func containerOpensV1AndPersistsToDisk() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "sheafnote-\(UUID()).store")
        defer { for suffix in ["", "-shm", "-wal"] { try? FileManager.default.removeItem(atPath: url.path + suffix) } }
        do {
            let c = try SheafnoteStore.makeContainer(url: url)
            let lib = LibraryStore(context: c.mainContext)
            _ = try lib.createNotebook(title: "Persist", kind: .paged, cover: .default, template: .blank, paperSize: .a4,
                                       orientation: .portrait, paperColor: .white, in: nil)
        }
        let reopened = try SheafnoteStore.makeContainer(url: url)
        let titles = try LibraryStore(context: reopened.mainContext).allNotebooks().map(\.title)
        #expect(titles == ["Persist"])
    }

    @Test func schemaListsAllModelsAndNoStagesYet() {
        #expect(SheafnoteSchemaV1.models.count == 13)
        #expect(SheafnoteMigrationPlan.stages.isEmpty)
        #expect(SheafnoteSchemaV1.versionIdentifier == Schema.Version(1, 0, 0))
    }

    @Test func recordTypesAreUniqueAndPrefixed() {
        let types = [Folder.recordType, Notebook.recordType, Page.recordType, PageElement.recordType, Asset.recordType,
                     OutlineEntry.recordType, Bookmark.recordType, AudioRecording.recordType, Flashcard.recordType,
                     StudyState.recordType, SavedElement.recordType, AppSetting.recordType]
        #expect(Set(types).count == 12)
        #expect(types.allSatisfy { $0.hasPrefix("SN") })
    }

    @Test func everyModelCanBeInsertedAndFetched() throws {
        let c = try SheafnoteStore.makeContainer(inMemory: true)
        defer { withExtendedLifetime(c) {} }
        let ctx = c.mainContext
        let nid = UUID(), pid = UUID()
        ctx.insert(Asset(kind: .audio, data: Data([1]), sha256: "h"))
        ctx.insert(OutlineEntry(notebookID: nid, title: "t", pageID: pid, sortKey: "V"))
        ctx.insert(AudioRecording(notebookID: nid, assetID: UUID(), title: "r", startedAt: .now, duration: 3))
        let card = Flashcard(notebookID: nid, deck: "d", frontImage: Data([1]), backImage: Data([2]))
        ctx.insert(card)
        ctx.insert(StudyState(flashcardID: card.id))
        ctx.insert(PageRevision(pageID: pid, notebookID: nid, reason: .restore, inkData: nil, strokeIDs: [], elements: Data()))
        try ctx.save()
        #expect(try ctx.fetch(FetchDescriptor<StudyState>()).first?.ease == 2.5)
        #expect(try ctx.fetch(FetchDescriptor<Asset>()).first?.kind == .audio)
    }

    @Test func elementValueRoundTripThroughRow() {
        let v = ElementValue(pageID: UUID(), kind: .shape, frame: CGRect(x: 1, y: 2, width: 3, height: 4), rotation: 0.5,
                             zIndex: 7, payload: Data([1]), assetID: UUID())
        #expect(PageElement(value: v).value == v)
    }

    @Test func payloadsRoundTrip() {
        let link = LinkPayload(target: .url(URL(string: "https://example.com")!), label: "x")
        #expect(PayloadCodec.decode(LinkPayload.self, from: PayloadCodec.encode(link)) == link)
        let text = TextPayload(text: "hi", link: .page(UUID()))
        #expect(PayloadCodec.decode(TextPayload.self, from: PayloadCodec.encode(text)) == text)
        let shape = ShapePayload(shapeKind: .arrow, points: [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 1)], fillHex: "#FF0000")
        #expect(PayloadCodec.decode(ShapePayload.self, from: PayloadCodec.encode(shape)) == shape)
        let tape = TapePayload(colorHex: "#00FF00")
        #expect(PayloadCodec.decode(TapePayload.self, from: PayloadCodec.encode(tape))?.isRevealed == false)
        let img = ImagePayload(originalSize: CGSize(width: 10, height: 20))
        #expect(PayloadCodec.decode(ImagePayload.self, from: PayloadCodec.encode(img)) == img)
        let sticker = StickerPayload(stickerID: "star", tintHex: nil)
        #expect(PayloadCodec.decode(StickerPayload.self, from: PayloadCodec.encode(sticker)) == sticker)
        #expect(PayloadCodec.decode(TextPayload.self, from: Data("junk".utf8)) == nil)
    }
}
