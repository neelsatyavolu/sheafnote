import Foundation
import SwiftData
import Testing
@testable import SheafnoteCore

@MainActor
@Suite("Sheafnote archive round trip")
struct ArchiveRoundTripTests {
    struct World {
        let source: StoreFixture
        var notebookID: UUID
        var pageIDs: [UUID]
        var assetID: UUID
    }

    private func tempURL(_ ext: String = "sheafnote") -> URL {
        FileManager.default.temporaryDirectory.appending(path: "archive-\(UUID().uuidString).\(ext)")
    }

    /// A folder, a notebook with PDF background, ink, an element that links to another page, outline, bookmark.
    private func makeWorld() throws -> World {
        let fx = try StoreFixture()
        let folder = try fx.library.createFolder(name: "School", in: nil)
        let nb = try fx.notebook("Biology", in: folder.id)
        let first = try fx.pages.orderedPages(of: nb.id)[0]
        let second = try fx.pages.addPage(to: nb.id, at: .end, template: TemplateSpec(kind: .gridMedium))
        let asset = try fx.pages.importAsset(data: Data("%PDF-1.4 fake".utf8), kind: .pdf, filename: "book.pdf", uti: "com.adobe.pdf")
        first.backgroundAssetID = asset.id
        first.backgroundPageIndex = 3
        try fx.pages.saveInk(pageID: first.id, drawingData: Data((0..<2000).map { UInt8($0 % 200) }), strokeIDs: [StrokeID(rawValue: "s1"), StrokeID(rawValue: "s2")])
        let link = LinkPayload(target: .page(second.id), label: "see page 2")
        try fx.pages.insertElement(ElementValue(pageID: first.id, kind: .link, frame: CGRect(x: 10, y: 20, width: 30, height: 40),
                                                rotation: 0.5, zIndex: 3, payload: PayloadCodec.encode(link)))
        fx.context.insert(OutlineEntry(notebookID: nb.id, title: "Chapter 1", pageID: first.id, pdfPageIndex: 3, sortKey: "V", source: .pdf))
        fx.context.insert(Bookmark(notebookID: nb.id, pageID: second.id, title: "Remember"))
        nb.isFavorite = true
        try fx.context.save()
        return World(source: fx, notebookID: nb.id, pageIDs: [first.id, second.id], assetID: asset.id)
    }

    private func export(_ world: World, _ selection: ArchiveSelection) async throws -> URL {
        let url = tempURL()
        try await ArchiveExporter(context: world.source.context).export(selection, to: url)
        return url
    }

    @Test func libraryRoundTripsIntoAFreshStoreWithNewIds() async throws {
        let world = try makeWorld()
        let url = try await export(world, .library)
        defer { try? FileManager.default.removeItem(at: url) }

        let target = try StoreFixture()
        let summary = try await ArchiveImporter(context: target.context, pages: target.pages).importArchive(from: url)

        #expect(summary.manifest.counts.notebooks == 1)
        #expect(summary.notebookIDs.count == 1 && summary.notebookIDs[0] != world.notebookID)
        let nb = try #require(target.library.notebook(id: summary.notebookIDs[0]))
        #expect(nb.title == "Biology" && nb.isFavorite)
        let folderID = try #require(nb.folderID)
        let folder = try #require(target.library.folder(id: folderID))
        #expect(folder.name == "School")
        let pages = try target.pages.orderedPages(of: nb.id)
        #expect(pages.count == 2)
        #expect(pages[0].backgroundPageIndex == 3)
        #expect(pages[0].strokeIDs == ["s1", "s2"])
        #expect(pages[0].inkData == Data((0..<2000).map { UInt8($0 % 200) }))
        #expect(pages[1].template?.kind == .gridMedium)
        let bgID = try #require(pages[0].backgroundAssetID)
        let bgAsset = try await target.pages.data(for: bgID)
        #expect(bgAsset == Data("%PDF-1.4 fake".utf8))
    }

    @Test func linksAndOutlineFollowTheNewIds() async throws {
        let world = try makeWorld()
        let url = try await export(world, .library)
        defer { try? FileManager.default.removeItem(at: url) }
        let target = try StoreFixture()
        let summary = try await ArchiveImporter(context: target.context, pages: target.pages).importArchive(from: url)
        let pages = try target.pages.orderedPages(of: summary.notebookIDs[0])
        let elements = try target.pages.elements(on: pages[0].id)
        let element = try #require(elements.first)
        let payload = try #require(PayloadCodec.decode(LinkPayload.self, from: element.payload))
        #expect(payload.target == .page(pages[1].id))
        #expect(element.frame == CGRect(x: 10, y: 20, width: 30, height: 40) && element.zIndex == 3)
        let outline = try target.context.fetch(FetchDescriptor<OutlineEntry>())
        #expect(outline.count == 1 && outline[0].pageID == pages[0].id && outline[0].notebookID == summary.notebookIDs[0])
        let bookmarks = try target.context.fetch(FetchDescriptor<Bookmark>())
        #expect(bookmarks.count == 1 && bookmarks[0].pageID == pages[1].id)
    }

    @Test func importingIntoTheSameLibraryAddsCopiesAndNeverTouchesTheOriginal() async throws {
        let world = try makeWorld()
        let url = try await export(world, .library)
        defer { try? FileManager.default.removeItem(at: url) }
        let before = try world.source.library.allNotebooks().count
        let importer = ArchiveImporter(context: world.source.context, pages: world.source.pages)
        let summary = try await importer.importArchive(from: url, wrapperFolderName: "Backup 2026-10-23")
        #expect(try world.source.library.allNotebooks().count == before + 1)
        #expect(!summary.notebookIDs.contains(world.notebookID))
        let original = try #require(world.source.library.notebook(id: world.notebookID))
        #expect(original.deletedAt == nil)
        let copy = try #require(world.source.library.notebook(id: summary.notebookIDs[0]))
        let wrapper = try #require(world.source.library.folder(id: summary.folderIDs[0]))
        #expect(wrapper.name == "Backup 2026-10-23")
        #expect(summary.folderIDs.count == 2)
        let copiedFolderID = try #require(copy.folderID)
        let copiedFolder = try #require(world.source.library.folder(id: copiedFolderID))
        #expect(copiedFolder.parentID == wrapper.id)
        // The attached file is shared, not duplicated.
        #expect(try world.source.context.fetch(FetchDescriptor<Asset>()).count == 1)
    }

    @Test func singleNotebookExportContainsOnlyThatNotebook() async throws {
        let world = try makeWorld()
        _ = try world.source.notebook("Other")
        let url = try await export(world, .notebooks([world.notebookID]))
        defer { try? FileManager.default.removeItem(at: url) }
        let target = try StoreFixture()
        let importer = ArchiveImporter(context: target.context, pages: target.pages)
        #expect(try importer.inspect(url: url).scope == .notebooks)
        let summary = try await importer.importArchive(from: url)
        #expect(summary.manifest.counts.notebooks == 1 && summary.folderIDs.isEmpty)
        let notebook = try #require(target.library.notebook(id: summary.notebookIDs[0]))
        #expect(notebook.folderID == nil)
    }

    @Test func softDeletedItemsAreNotExported() async throws {
        let world = try makeWorld()
        let gone = try world.source.notebook("Trash")
        try world.source.library.softDelete([.notebook(gone.id)])
        let url = try await export(world, .library)
        defer { try? FileManager.default.removeItem(at: url) }
        let manifest = try ArchiveImporter(context: world.source.context, pages: world.source.pages).inspect(url: url)
        #expect(manifest.counts.notebooks == 1)
    }

    @Test func exportIsDeterministicForTheSameDate() async throws {
        let world = try makeWorld()
        let a = tempURL(), b = tempURL()
        defer { try? FileManager.default.removeItem(at: a); try? FileManager.default.removeItem(at: b) }
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let exporter = ArchiveExporter(context: world.source.context)
        try await exporter.export(.library, to: a, now: date)
        try await exporter.export(.library, to: b, now: date)
        #expect(try Data(contentsOf: a) == Data(contentsOf: b))
    }

    @Test func textNotebookKeepsItsRichText() async throws {
        let fx = try StoreFixture()
        let doc = try fx.notebook("Essay", kind: .text)
        doc.richText = Data("{\"blocks\":[]}".utf8)
        try fx.context.save()
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try await ArchiveExporter(context: fx.context).export(.library, to: url)
        let target = try StoreFixture()
        let summary = try await ArchiveImporter(context: target.context, pages: target.pages).importArchive(from: url)
        let copy = try #require(target.library.notebook(id: summary.notebookIDs[0]))
        #expect(copy.kind == .text && copy.richText == Data("{\"blocks\":[]}".utf8))
    }

    @Test func flashcardsAudioAndSavedElementsRoundTrip() async throws {
        let fx = try StoreFixture()
        let nb = try fx.notebook("Study")
        let page = try fx.pages.orderedPages(of: nb.id)[0]
        let audio = try fx.pages.importAsset(data: Data(repeating: 9, count: 64), kind: .audio, filename: "a.m4a")
        let timeline = Data("[{\"pageID\":\"\(page.id.uuidString)\",\"offset\":1.5}]".utf8)
        fx.context.insert(AudioRecording(notebookID: nb.id, assetID: audio.id, title: "Lecture", startedAt: .now, duration: 12, timeline: timeline))
        let card = Flashcard(notebookID: nb.id, deck: "Deck", sourcePageID: page.id, frontImage: Data([1, 2]), backImage: Data([3, 4]), frontText: "Q", backText: "A")
        fx.context.insert(card)
        let state = StudyState(flashcardID: card.id)
        state.ease = 2.1; state.lapses = 2
        fx.context.insert(state)
        fx.context.insert(SavedElement(name: "Arrow", category: "Marks", width: 5, height: 6, inkData: Data([7]), elements: Data("[]".utf8), thumbnail: Data([8])))
        try fx.context.save()
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try await ArchiveExporter(context: fx.context).export(.library, to: url)

        let target = try StoreFixture()
        let summary = try await ArchiveImporter(context: target.context, pages: target.pages).importArchive(from: url)
        let newPage = try target.pages.orderedPages(of: summary.notebookIDs[0])[0]
        let recordings = try target.context.fetch(FetchDescriptor<AudioRecording>())
        let recording = try #require(recordings.first)
        #expect(String(decoding: recording.timeline, as: UTF8.self).contains(newPage.id.uuidString))
        let cards = try target.context.fetch(FetchDescriptor<Flashcard>())
        let copyCard = try #require(cards.first)
        #expect(copyCard.frontImage == Data([1, 2]) && copyCard.sourcePageID == newPage.id)
        let states = try target.context.fetch(FetchDescriptor<StudyState>())
        let copyState = try #require(states.first)
        #expect(copyState.flashcardID == copyCard.id && copyState.ease == 2.1 && copyState.lapses == 2)
        let savedRows = try target.context.fetch(FetchDescriptor<SavedElement>())
        let saved = try #require(savedRows.first)
        #expect(saved.name == "Arrow" && saved.inkData == Data([7]) && saved.thumbnail == Data([8]))
    }
}
