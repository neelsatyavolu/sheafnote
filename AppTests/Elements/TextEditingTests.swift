import SwiftUI
import Testing
import UIKit
import SheafnoteCore
@testable import Sheafnote

@MainActor
@Suite struct TextEditingTests {
    private func texts(_ page: PageSession) -> [ElementValue] { page.elementValues.filter { $0.kind == .text } }

    @Test func newBoxWithTextIsCreatedOnCommit() throws {
        let f = try ElementsFixture()
        let page = try f.page()
        let session = TextEditSession()
        session.beginNew(at: CGPoint(x: 50, y: 60), style: TextPayload(text: "", fontSize: 24, isBold: true), on: page)
        #expect(session.isEditing && session.isNew)
        session.working.text = "Hello"
        let stored = try #require(try session.commit())
        #expect(!session.isEditing)
        let box = try #require(texts(page).first)
        #expect(box.id == stored.id)
        #expect(box.frame.origin == CGPoint(x: 50, y: 60))
        let payload = try #require(box.decoded(TextPayload.self))
        #expect(payload.text == "Hello" && payload.isBold && payload.fontSize == 24)
    }

    @Test func emptyNewBoxIsNeverCreated() throws {
        let f = try ElementsFixture()
        let page = try f.page()
        let session = TextEditSession()
        session.beginNew(at: .zero, style: TextPayload(text: ""), on: page)
        session.working.text = "  \n "
        #expect(try session.commit() == nil)
        #expect(texts(page).isEmpty)
    }

    @Test func editingAnExistingBoxIsOneUndoStep() async throws {
        let f = try ElementsFixture()
        let page = try f.page()
        let original = try page.elements.add(
            ElementValue(pageID: page.pageID, kind: .text, frame: CGRect(x: 10, y: 10, width: 200, height: 40),
                         payload: PayloadCodec.encode(TextPayload(text: "one"))), undoName: "Add")
        await EditorFixture.settle()
        let session = TextEditSession()
        session.begin(existing: original, on: page)
        session.working.text = "two"
        session.working.isItalic = true
        try session.commit()
        #expect(try #require(texts(page).first?.decoded(TextPayload.self)).text == "two")
        await EditorFixture.settle()
        f.session.undo()
        let reverted = try #require(texts(page).first?.decoded(TextPayload.self))
        #expect(reverted.text == "one" && !reverted.isItalic)
    }

    @Test func unchangedEditWritesNothing() async throws {
        let f = try ElementsFixture()
        let page = try f.page()
        let element = try page.elements.add(
            ElementValue(pageID: page.pageID, kind: .text, frame: CGRect(x: 10, y: 10, width: 200, height: 40),
                         payload: PayloadCodec.encode(TextPayload(text: "same"))), undoName: "Add")
        let before = try f.services.pages.elements(on: page.pageID)
        let session = TextEditSession()
        session.begin(existing: element, on: page)
        try session.commit()
        #expect(try f.services.pages.elements(on: page.pageID) == before)
    }

    @Test func clearingAnExistingBoxRemovesItButUndoBringsItBack() async throws {
        let f = try ElementsFixture()
        let page = try f.page()
        let element = try page.elements.add(
            ElementValue(pageID: page.pageID, kind: .text, frame: CGRect(x: 10, y: 10, width: 200, height: 40),
                         payload: PayloadCodec.encode(TextPayload(text: "bye"))), undoName: "Add")
        await EditorFixture.settle()
        let session = TextEditSession()
        session.begin(existing: element, on: page)
        session.working.text = ""
        #expect(try session.commit() == nil)
        #expect(texts(page).isEmpty)
        await EditorFixture.settle()
        f.session.undo()
        #expect(texts(page).count == 1)
    }

    @Test func boxGrowsToFitLongText() throws {
        let f = try ElementsFixture()
        let page = try f.page()
        let session = TextEditSession()
        session.beginNew(at: .zero, style: TextPayload(text: "", fontSize: 20), on: page)
        session.working.text = Array(repeating: "A line of text that wraps around", count: 8).joined(separator: "\n")
        let stored = try #require(try session.commit())
        #expect(stored.frame.height > TextBoxLayout.defaultSize.height * 3)
    }

    @Test func leavingTheTextToolCommitsTypedText() async throws {
        let f = try ElementsFixture()
        let page = try f.page()
        f.session.toolState.select(.text)
        await EditorFixture.settle()
        let tool = try #require(f.host.tools.tool(.text) as? TextTool)
        tool.editing.beginNew(at: CGPoint(x: 20, y: 20), style: TextPayload(text: ""), on: page)
        tool.editing.working.text = "typed before switching"
        f.session.toolState.select(.pen)
        await EditorFixture.settle()
        #expect(!tool.editing.isEditing)
        #expect(texts(page).first?.decoded(TextPayload.self)?.text == "typed before switching")
    }

    @Test func beginEditingFromTheRendererSwitchesToTheTextTool() throws {
        let f = try ElementsFixture()
        let page = try f.page()
        let renderer = try #require(f.host.elementRenderers.renderer(for: .text))
        let element = try page.elements.add(
            ElementValue(pageID: page.pageID, kind: .text, frame: CGRect(x: 0, y: 0, width: 200, height: 40),
                         payload: PayloadCodec.encode(TextPayload(text: "keep"))), undoName: "Add")
        renderer.beginEditing(element, page: page, editor: f.session)
        #expect(f.session.toolState.activeToolID == .text)
        let tool = try #require(f.host.tools.tool(.text) as? TextTool)
        #expect(tool.editing.isEditing(element.id))
    }

    @Test func styleTargetEditsTheSelectedBoxAndRemembersDefaults() throws {
        let f = try ElementsFixture()
        let page = try f.page()
        let suite = UserDefaults.standard
        let saved = suite.data(forKey: "elements.textDefaults")
        defer { if let saved { suite.set(saved, forKey: "elements.textDefaults") } else { suite.removeObject(forKey: "elements.textDefaults") } }
        let element = try page.elements.add(
            ElementValue(pageID: page.pageID, kind: .text, frame: CGRect(x: 0, y: 0, width: 200, height: 40),
                         payload: PayloadCodec.encode(TextPayload(text: "style me"))), undoName: "Add")
        ElementSelecting.select(element, on: page, editor: f.session, host: f.host)
        let target = TextStyleTarget(session: TextEditSession(), editor: f.session)
        #expect(target.hasTarget)
        target.apply { $0.isBold = true; $0.colorHex = "#FF0000"; $0.fontSize = 40 }
        let changed = try #require(texts(page).first?.decoded(TextPayload.self))
        #expect(changed.isBold && changed.colorHex == "#FF0000" && changed.fontSize == 40 && changed.text == "style me")
        let defaults = TextDefaultsStore.load()
        #expect(defaults.isBold && defaults.text.isEmpty && defaults.fontSize == 40)
    }

    @Test func styleTargetWithoutSelectionOnlySetsDefaults() throws {
        let f = try ElementsFixture()
        let suite = UserDefaults.standard
        let saved = suite.data(forKey: "elements.textDefaults")
        defer { if let saved { suite.set(saved, forKey: "elements.textDefaults") } else { suite.removeObject(forKey: "elements.textDefaults") } }
        let target = TextStyleTarget(session: TextEditSession(), editor: f.session)
        #expect(!target.hasTarget)
        target.apply { $0.alignment = .center }
        #expect(TextDefaultsStore.load().alignment == .center)
    }

    @Test func fontsResolveWithTraits() {
        let regular = TextStyling.font(for: TextPayload(text: "", fontSize: 20))
        let bold = TextStyling.font(for: TextPayload(text: "", fontSize: 20, isBold: true))
        let italic = TextStyling.font(for: TextPayload(text: "", fontSize: 20, isItalic: true))
        #expect(bold.fontDescriptor.symbolicTraits.contains(.traitBold))
        #expect(italic.fontDescriptor.symbolicTraits.contains(.traitItalic))
        #expect(!regular.fontDescriptor.symbolicTraits.contains(.traitBold))
        #expect(regular.pointSize == 20)
        for choice in TextStyling.fontChoices {
            #expect(TextStyling.font(for: TextPayload(text: "", fontName: choice.id)).pointSize == 18, "font \(choice.id)")
        }
        #expect(TextStyling.font(for: TextPayload(text: "", fontName: "No Such Font")).pointSize == 18)
    }

    @Test func attributesCarryColorUnderlineAndAlignment() {
        let attrs = TextStyling.attributes(for: TextPayload(text: "x", colorHex: "#FF0000", isUnderlined: true, alignment: .center))
        #expect((attrs[.foregroundColor] as? UIColor)?.hexString == "#FF0000")
        #expect(attrs[.underlineStyle] as? Int == NSUnderlineStyle.single.rawValue)
        #expect((attrs[.paragraphStyle] as? NSParagraphStyle)?.alignment == .center)
    }

    @Test func contentHeightGrowsWithTextAndShrinksWithWidth() {
        let one = TextStyling.contentHeight(for: TextPayload(text: "short"), width: 300)
        let many = TextStyling.contentHeight(for: TextPayload(text: "short\nshort\nshort"), width: 300)
        let narrow = TextStyling.contentHeight(for: TextPayload(text: "a rather long sentence that must wrap"), width: 80)
        #expect(many > one * 2)
        #expect(narrow > one * 2)
    }
}
