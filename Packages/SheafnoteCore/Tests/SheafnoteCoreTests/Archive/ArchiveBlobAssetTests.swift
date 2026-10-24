import Foundation
import SwiftData
import Testing
@testable import SheafnoteCore

@MainActor
@Suite("Archive keeps images referenced from JSON blobs")
struct ArchiveBlobAssetTests {
    @Test func savedElementAndTextDocumentImagesSurviveBackupAndRestore() async throws {
        let source = try StoreFixture()
        let doc = try source.notebook("Essay", kind: .text)
        let page = try source.notebook("Pages")
        let pageRow = try #require(try source.pages.orderedPages(of: page.id).first)
        let savedImage = try source.pages.importAsset(data: Data([1, 2, 3]), kind: .image, filename: "s.png")
        let docImage = try source.pages.importAsset(data: Data([4, 5, 6]), kind: .image, filename: "d.png")
        doc.richText = RichTextDocument(blocks: [RichTextBlock(kind: .image, assetID: docImage.id)]).encoded()
        let value = ElementValue(pageID: pageRow.id, kind: .image, frame: .zero, assetID: savedImage.id)
        source.context.insert(SavedElement(name: "Pic", category: "Mine", width: 1, height: 1, inkData: nil,
                                           elements: JSONCoding.encode([value]), thumbnail: Data([9])))
        try source.context.save()

        let url = FileManager.default.temporaryDirectory.appending(path: "blob-\(UUID().uuidString).sheafnote")
        defer { try? FileManager.default.removeItem(at: url) }
        let manifest = try await ArchiveExporter(context: source.context).export(.library, to: url)
        #expect(manifest.counts.assets == 2)

        let target = try StoreFixture()
        let summary = try await ArchiveImporter(context: target.context, pages: target.pages).importArchive(from: url)

        let restoredDoc = try #require(summary.notebookIDs.compactMap { target.library.notebook(id: $0) }.first { $0.kind == .text })
        let blockAsset = try #require((try RichTextDocument.decode(restoredDoc.richText ?? Data())).blocks.first?.assetID)
        #expect(try await target.pages.data(for: blockAsset) == Data([4, 5, 6]))

        let saved = try #require(try target.context.fetch(FetchDescriptor<SavedElement>()).first)
        let elements = try #require(JSONCoding.decode([ElementValue].self, from: saved.elements))
        let savedAsset = try #require(elements.first?.assetID)
        #expect(try await target.pages.data(for: savedAsset) == Data([1, 2, 3]))
    }

    @Test func failedImportLeavesNoStrayAssets() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "bad-\(UUID().uuidString).sheafnote")
        defer { try? FileManager.default.removeItem(at: url) }
        let source = try StoreFixture()
        let nb = try source.notebook("A")
        let page = try #require(try source.pages.orderedPages(of: nb.id).first)
        let image = try source.pages.importAsset(data: Data([1, 1]), kind: .image, filename: nil)
        try source.pages.insertElement(ElementValue(pageID: page.id, kind: .image, frame: .zero, assetID: image.id))
        try await ArchiveExporter(context: source.context).export(.library, to: url)

        let target = try StoreFixture()
        let task = Task { @MainActor in
            try await ArchiveImporter(context: target.context, pages: target.pages).importArchive(from: url)
        }
        task.cancel()
        _ = try? await task.value
        #expect(try target.context.fetch(FetchDescriptor<Asset>()).isEmpty)
        #expect(try target.context.fetch(FetchDescriptor<Notebook>()).isEmpty)
    }
}
