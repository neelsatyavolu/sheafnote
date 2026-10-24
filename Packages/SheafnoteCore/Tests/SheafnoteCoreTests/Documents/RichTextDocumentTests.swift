import Foundation
import Testing
@testable import SheafnoteCore

@Suite struct RichTextDocumentTests {
    @Test func emptyDocumentHasOneParagraph() {
        let doc = RichTextDocument.empty
        #expect(doc.blocks.count == 1)
        #expect(doc.blocks[0].kind == .paragraph)
        #expect(doc.plainText.isEmpty)
    }

    @Test func codecRoundTrips() throws {
        var doc = RichTextDocument.empty
        let id = doc.blocks[0].id
        doc = doc.settingText("Title", for: id).settingKind(.heading1, for: id)
        let decoded = try RichTextDocument.decode(doc.encoded())
        #expect(decoded == doc)
        #expect(decoded.version == RichTextDocument.currentVersion)
    }

    @Test func decodeFailureThrowsInsteadOfReturningEmpty() {
        #expect(throws: RichTextError.self) { try RichTextDocument.decode(Data("not json".utf8)) }
    }

    @Test func decodeIgnoresUnknownFieldsAndKinds() throws {
        let json = #"{"version":1,"future":true,"blocks":[{"id":"00000000-0000-0000-0000-000000000001","kind":"hologram","text":"x","extra":1}]}"#
        let doc = try RichTextDocument.decode(Data(json.utf8))
        #expect(doc.blocks.count == 1)
        #expect(doc.blocks[0].text == "x")
        #expect(doc.blocks[0].kind == .paragraph)
    }

    @Test func newerVersionIsRejectedSoItIsNeverOverwritten() {
        let json = #"{"version":99,"blocks":[]}"#
        #expect(throws: RichTextError.self) { try RichTextDocument.decode(Data(json.utf8)) }
    }

    @Test func typingNewlineSplitsTheBlock() {
        let doc = RichTextDocument.empty
        let id = doc.blocks[0].id
        let (after, focus) = doc.applyingEdit("Hello\nWorld", to: id)
        #expect(after.blocks.map(\.text) == ["Hello", "World"])
        #expect(focus == after.blocks[1].id)
    }

    @Test func newlineInListContinuesTheList() {
        let doc = RichTextDocument.empty
        let id = doc.blocks[0].id
        let list = doc.settingKind(.checklist, for: id)
        let (after, _) = list.applyingEdit("Milk\n", to: id)
        #expect(after.blocks.count == 2)
        #expect(after.blocks[1].kind == .checklist)
        #expect(after.blocks[1].checked == false)
    }

    @Test func newlineAfterHeadingStartsAParagraph() {
        let doc = RichTextDocument.empty
        let id = doc.blocks[0].id
        let (after, _) = doc.settingKind(.heading2, for: id).applyingEdit("Section\n", to: id)
        #expect(after.blocks[1].kind == .paragraph)
    }

    @Test func newlineInEmptyListItemEndsTheList() {
        let doc = RichTextDocument.empty
        let id = doc.blocks[0].id
        let (after, _) = doc.settingKind(.bullet, for: id).applyingEdit("\n", to: id)
        #expect(after.blocks.count == 1)
        #expect(after.blocks[0].kind == .paragraph)
    }

    @Test func togglingChecklistOnlyAffectsChecklists() {
        let doc = RichTextDocument.empty
        let id = doc.blocks[0].id
        #expect(doc.togglingChecked(for: id).blocks[0].checked == false)
        let list = doc.settingKind(.checklist, for: id).togglingChecked(for: id)
        #expect(list.blocks[0].checked)
        #expect(list.togglingChecked(for: id).blocks[0].checked == false)
    }

    @Test func leavingChecklistClearsCheckedState() {
        let doc = RichTextDocument.empty
        let id = doc.blocks[0].id
        let after = doc.settingKind(.checklist, for: id).togglingChecked(for: id).settingKind(.paragraph, for: id)
        #expect(after.blocks[0].checked == false)
    }

    @Test func numberedItemsCountConsecutiveRuns() {
        let doc = RichTextDocument(blocks: [
            RichTextBlock(kind: .numbered, text: "a"), RichTextBlock(kind: .numbered, text: "b"),
            RichTextBlock(kind: .paragraph, text: "break"), RichTextBlock(kind: .numbered, text: "c"),
        ])
        #expect(doc.numbers == [1, 2, nil, 1])
        let joined = doc.removingBlock(doc.blocks[2].id)
        #expect(joined.numbers == [1, 2, 3])
    }

    @Test func removingTheLastBlockLeavesAnEmptyParagraph() {
        let doc = RichTextDocument.empty
        let after = doc.removingBlock(doc.blocks[0].id)
        #expect(after.blocks.count == 1)
        #expect(after.blocks[0].kind == .paragraph)
    }

    @Test func insertingAnImageAddsImageBlockAndTrailingParagraph() {
        let doc = RichTextDocument.empty
        let asset = UUID()
        let (after, _) = doc.insertingImage(asset, after: doc.blocks[0].id)
        #expect(after.blocks.contains { $0.kind == .image && $0.assetID == asset })
        #expect(after.blocks.last?.kind == .paragraph)
    }

    @Test func formattingToggles() {
        let doc = RichTextDocument.empty
        let id = doc.blocks[0].id
        let bold = doc.togglingStyle(.bold, for: id)
        #expect(bold.blocks[0].bold && !bold.blocks[0].italic)
        #expect(bold.togglingStyle(.bold, for: id).blocks[0].bold == false)
        #expect(doc.togglingStyle(.underline, for: id).blocks[0].underline)
        #expect(doc.togglingStyle(.italic, for: id).blocks[0].italic)
    }

    @Test func plainTextJoinsBlocksAndMarksLists() {
        let doc = RichTextDocument(blocks: [
            RichTextBlock(kind: .heading1, text: "Plan"),
            RichTextBlock(kind: .bullet, text: "one"),
            RichTextBlock(kind: .checklist, text: "two", checked: true),
            RichTextBlock(kind: .numbered, text: "three"),
        ])
        #expect(doc.plainText == "Plan\n• one\n☑ two\n1. three")
        #expect(doc.searchableText == "Plan\none\ntwo\nthree")
    }

    @Test func movingABlock() {
        let a = RichTextBlock(text: "a"), b = RichTextBlock(text: "b"), c = RichTextBlock(text: "c")
        let doc = RichTextDocument(blocks: [a, b, c]).movingBlock(c.id, to: 0)
        #expect(doc.blocks.map(\.text) == ["c", "a", "b"])
    }

    @Test func unknownBlockIdsLeaveTheDocumentUnchanged() {
        let doc = RichTextDocument.empty
        let ghost = UUID()
        #expect(doc.settingText("x", for: ghost) == doc)
        #expect(doc.settingKind(.bullet, for: ghost) == doc)
        #expect(doc.removingBlock(ghost) == doc)
        #expect(doc.applyingEdit("x\ny", to: ghost).document == doc)
    }
}
