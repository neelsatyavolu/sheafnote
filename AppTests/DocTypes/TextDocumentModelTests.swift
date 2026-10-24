import Foundation
import Testing
import UIKit
import SheafnoteCore
@testable import Sheafnote

@MainActor
@Suite struct TextDocumentModelTests {
    func make() throws -> (TextDocumentModel, Notebook, AppServices) {
        let services = try AppServices.inMemory()
        let nb = try DocumentCreation.make(kind: .text, title: "T", cover: "ledger", services: services, folder: nil)
        return (TextDocumentModel(notebook: nb, services: services), nb, services)
    }

    @Test func typingIsSavedOnFlushAndMarksTheNotebookDirty() throws {
        let (model, nb, _) = try make()
        nb.syncDirty = false
        nb.dirtyFields = []
        model.edit(text: "Hello", in: model.document.blocks[0].id)
        model.flush()
        let saved = try RichTextDocument.decode(try #require(nb.richText))
        #expect(saved.blocks[0].text == "Hello")
        #expect(nb.syncDirty && nb.dirtyFields.contains("richText"))
    }

    @Test func saveHappensOnItsOwnAfterAShortDelay() async throws {
        let (model, nb, _) = try make()
        model.edit(text: "Auto", in: model.document.blocks[0].id)
        try await Task.sleep(for: .milliseconds(1100))
        #expect(nb.richText != nil)
    }

    @Test func reopeningLoadsTheSavedText() throws {
        let (model, nb, services) = try make()
        model.edit(text: "Keep me", in: model.document.blocks[0].id)
        model.flush()
        let reopened = TextDocumentModel(notebook: nb, services: services)
        #expect(reopened.document.blocks[0].text == "Keep me")
    }

    @Test func unreadableTextIsNeverOverwritten() throws {
        let (_, nb, services) = try make()
        let junk = Data("{broken".utf8)
        nb.richText = junk
        let model = TextDocumentModel(notebook: nb, services: services)
        #expect(model.loadError != nil)
        #expect(!model.isEditable)
        model.edit(text: "typed", in: model.document.blocks[0].id)
        model.change { $0.settingKind(.bullet, for: $0.blocks[0].id) }
        model.flush()
        #expect(nb.richText == junk)
    }

    @Test func newerFormatIsKeptAsIs() throws {
        let (_, nb, services) = try make()
        let future = Data(#"{"version":42,"blocks":[]}"#.utf8)
        nb.richText = future
        let model = TextDocumentModel(notebook: nb, services: services)
        #expect(model.loadError != nil)
        model.flush()
        #expect(nb.richText == future)
    }

    @Test func newlineCreatesABlockAndMovesFocus() throws {
        let (model, _, _) = try make()
        model.edit(text: "One\nTwo", in: model.document.blocks[0].id)
        #expect(model.document.blocks.map(\.text) == ["One", "Two"])
        #expect(model.focusedBlock == model.document.blocks[1].id)
    }

    @Test func checklistFlowTypeToggleAndSave() throws {
        let (model, nb, _) = try make()
        let first = model.document.blocks[0].id
        model.change { $0.settingKind(.checklist, for: first) }
        model.edit(text: "Milk\nEggs", in: first)
        let second = model.document.blocks[1].id
        model.change { $0.togglingChecked(for: second) }
        model.flush()
        let saved = try RichTextDocument.decode(try #require(nb.richText))
        #expect(saved.blocks.map(\.kind) == [.checklist, .checklist])
        #expect(saved.blocks.map(\.checked) == [false, true])
    }

    @Test func undoAndRedoStepThroughStructuralChanges() throws {
        let (model, _, _) = try make()
        let id = model.document.blocks[0].id
        model.change { $0.settingKind(.heading1, for: id) }
        model.change { $0.togglingStyle(.bold, for: id) }
        #expect(model.canUndo && !model.canRedo)
        model.undo()
        #expect(!model.document.blocks[0].bold && model.document.blocks[0].kind == .heading1)
        model.undo()
        #expect(model.document.blocks[0].kind == .paragraph)
        model.redo()
        #expect(model.document.blocks[0].kind == .heading1)
        #expect(model.canRedo)
    }

    @Test func fastTypingIsOneUndoStep() throws {
        let (model, _, _) = try make()
        let id = model.document.blocks[0].id
        for text in ["H", "He", "Hel", "Hell", "Hello"] { model.edit(text: text, in: id) }
        model.undo()
        #expect(model.document.blocks[0].text.isEmpty)
        #expect(!model.canUndo)
    }

    @Test func insertingAPictureStoresAnAssetAndAnImageBlock() throws {
        let (model, nb, services) = try make()
        let image = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).pngData { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
        try model.insertImage(data: image)
        let imageBlock = try #require(model.document.blocks.first { $0.kind == .image })
        let assetID = try #require(imageBlock.assetID)
        #expect(model.document.blocks.last?.kind == .paragraph)
        model.flush()
        #expect(nb.richText != nil)
        #expect(try services.context.fetch(FetchDescriptorHelper.asset(assetID)).count == 1)
    }

    @Test func formattingAppliesToTheChosenBlockOnly() throws {
        let (model, _, _) = try make()
        model.edit(text: "a\nb", in: model.document.blocks[0].id)
        let second = model.document.blocks[1].id
        model.change { $0.togglingStyle(.italic, for: second) }
        #expect(model.document.blocks.map(\.italic) == [false, true])
    }
}

import SwiftData

private enum FetchDescriptorHelper {
    static func asset(_ id: UUID) -> FetchDescriptor<Asset> {
        FetchDescriptor<Asset>(predicate: #Predicate { $0.id == id })
    }
}
