import Foundation
import PencilKit
import SwiftData
import Testing
import SheafnoteCore
@testable import Sheafnote

@MainActor
@Suite struct TextDocumentSyncTests {
    private func make() throws -> (TextDocumentModel, Notebook, AppServices) {
        let services = try AppServices.inMemory()
        let nb = try DocumentCreation.make(kind: .text, title: "Essay", cover: "ledger", services: services, folder: nil)
        return (TextDocumentModel(notebook: nb, services: services), nb, services)
    }

    private func remoteText(_ s: String) -> Data {
        RichTextDocument(blocks: [RichTextBlock(text: s)]).encoded()
    }

    @Test func remoteTextIsShownWhenNothingIsUnsaved() throws {
        let (model, nb, _) = try make()
        nb.richText = remoteText("from the other device")
        NotificationCenter.default.post(name: .sheafnoteServerChangesApplied, object: nil)
        #expect(model.document.blocks.first?.text == "from the other device")
    }

    @Test func savingOverRemoteTextKeepsTheRemoteVersionAsACopy() throws {
        let (model, nb, services) = try make()
        model.edit(text: "typing here", in: model.document.blocks[0].id)
        nb.richText = remoteText("remote edit")           // sync wrote this while we had unsaved typing
        NotificationCenter.default.post(name: .sheafnoteServerChangesApplied, object: nil)
        #expect(model.document.blocks.first?.text == "typing here")
        model.flush()
        let copies = try services.context.fetch(FetchDescriptor<Notebook>()).filter { $0.title.hasSuffix(TextConflictCopy.titleSuffix) }
        #expect(copies.count == 1)
        #expect(try RichTextDocument.decode(try #require(copies[0].richText)).blocks.first?.text == "remote edit")
        #expect(try RichTextDocument.decode(try #require(nb.richText)).blocks.first?.text == "typing here")
    }
}

@MainActor
@Suite struct ReviewFixSupportTests {
    @Test func retentionRunsAfterEveryOtherBackgroundTask() {
        let registry = LibraryMenuRegistry()
        registry.registerBackgroundTask(id: LibraryMenuRegistry.retentionTaskID) { _ in }
        registry.registerBackgroundTask(id: "sync.foreground") { _ in }
        registry.registerBackgroundTask(id: "search.ocr") { _ in }
        #expect(registry.orderedBackgroundTasks.map(\.id) == ["sync.foreground", "search.ocr", LibraryMenuRegistry.retentionTaskID])
    }

    @Test func retentionWaitsOnlyWhenSyncCouldBeStale() {
        #expect(FoundationRegistrations.retentionShouldWait(for: .offline))
        #expect(FoundationRegistrations.retentionShouldWait(for: .error("x")))
        #expect(!FoundationRegistrations.retentionShouldWait(for: .idle))
        #expect(!FoundationRegistrations.retentionShouldWait(for: .signedOut))
        #expect(!FoundationRegistrations.retentionShouldWait(for: .localOnly))
    }

    @Test func colorSwatchesAreSpokenAsNamesNotHexCodes() {
        #expect(NamedColor.spokenName(forHex: "#1A73E8") == "Blue")
        #expect(NamedColor.spokenName(forHex: "not a color") == "not a color")
    }

    @Test func keeperLetsGoOfASessionOnceItsInkIsSaved() throws {
        let f = try EditorFixture()
        let page = try f.page()
        page.setDrawing(PKDrawingFactory.one(), undoName: "Draw")
        let keeper = UnsavedInkKeeper(retryInterval: .seconds(3600))
        #expect(keeper.settle(f.session))      // a working store saves right away
        #expect(keeper.heldCount == 0)
    }
}
