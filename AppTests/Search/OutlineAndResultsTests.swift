import Foundation
import SwiftUI
import Testing
import SheafnoteCore
@testable import Sheafnote

@MainActor
@Suite struct OutlineModelTests {
    private func setup(pages: Int = 4) throws -> (SearchFixture, Notebook, [Page], OutlineModel) {
        let f = try SearchFixture()
        let nb = try f.notebook("Book", pages: pages)
        let model = OutlineModel(notebookID: nb.id, services: f.services)
        model.reload()
        return (f, nb, try f.pages(of: nb), model)
    }

    private func titles(_ model: OutlineModel) -> [String] {
        model.userRows.map { String(repeating: "-", count: $0.depth) + $0.item.title }
    }

    @Test func addsEntriesThatPointAtPagesAndNumbersThem() throws {
        let (_, _, pages, model) = try setup()
        model.add(title: "Intro", pageID: pages[0].id)
        model.add(title: "Results", pageID: pages[2].id)
        #expect(titles(model) == ["Intro", "Results"])
        #expect(model.pageNumber(of: model.userRows[1].item) == 3)
        #expect(model.defaultTitle(forPage: pages[1].id) == "Page 2")
    }

    @Test func indentAndOutdentChangeNesting() throws {
        let (_, _, pages, model) = try setup()
        model.add(title: "A", pageID: pages[0].id)
        model.add(title: "B", pageID: pages[1].id)
        model.add(title: "C", pageID: pages[2].id)
        model.indent(model.userRows[1].item)
        #expect(titles(model) == ["A", "-B", "C"])
        model.indent(model.userRows[2].item)       // C joins A as a sibling of B? no: C's previous sibling is A
        #expect(titles(model) == ["A", "-B", "-C"])
        model.outdent(model.userRows[1].item)
        #expect(titles(model) == ["A", "-C", "B"])
    }

    @Test func firstEntryCannotBeIndented() throws {
        let (_, _, pages, model) = try setup()
        model.add(title: "Only", pageID: pages[0].id)
        model.indent(model.userRows[0].item)
        #expect(titles(model) == ["Only"])
        #expect(model.errorMessage == nil)
    }

    @Test func dragReorderMovesTheEntry() throws {
        let (_, _, pages, model) = try setup()
        for (i, name) in ["A", "B", "C"].enumerated() { model.add(title: name, pageID: pages[i].id) }
        model.move(from: IndexSet(integer: 2), to: 0)
        #expect(titles(model) == ["C", "A", "B"])
        model.move(from: IndexSet(integer: 0), to: 3)
        #expect(titles(model) == ["A", "B", "C"])
    }

    @Test func renameRemoveAndRetarget() throws {
        let (_, _, pages, model) = try setup()
        model.add(title: "Old", pageID: pages[0].id)
        let item = model.userRows[0].item
        model.rename(item, to: "New")
        model.point(item, to: pages[3].id)
        #expect(model.userRows[0].item.title == "New")
        #expect(model.pageNumber(of: model.userRows[0].item) == 4)
        model.rename(item, to: "  ")
        #expect(model.errorMessage != nil)
        model.errorMessage = nil
        model.remove(item)
        #expect(model.userRows.isEmpty)
    }

    @Test func pdfOutlineIsShownSeparatelyAndResolvesThroughPdfPages() throws {
        let (f, nb, pages, model) = try setup()
        pages[2].backgroundPageIndex = 7
        f.services.context.insert(OutlineEntry(notebookID: nb.id, title: "Chapter 3", pageID: nil, pdfPageIndex: 7,
                                               sortKey: "a", source: .pdf))
        try f.services.context.save()
        model.reload()
        #expect(model.userRows.isEmpty)
        #expect(model.pdfRows.map(\.item.title) == ["Chapter 3"])
        #expect(model.targetPage(of: model.pdfRows[0].item) == pages[2].id)
        #expect(model.pageNumber(of: model.pdfRows[0].item) == 3)
    }
}

@MainActor
@Suite struct SearchResultsModelTests {
    @Test func groupsTitlesAndPagesWithPageNumbers() async throws {
        let f = try SearchFixture()
        let a = try f.notebook("Orbit mechanics", pages: 3)
        let b = try f.notebook("Cooking")
        try f.pages(of: a)[2].recognizedText = "orbit of the moon"
        try f.pages(of: b)[0].recognizedText = "boil water"
        _ = try f.services.library.createFolder(name: "Orbital", in: nil)
        try f.services.context.save()
        await f.service.refreshIndex()

        let model = SearchResultsModel(service: f.service)
        model.update(query: "orbit")
        #expect(model.titles.count == 2)
        #expect(model.pages.count == 1)
        #expect(model.pages[0].pageNumber == 3)
        #expect(model.pages[0].notebookTitle == "Orbit mechanics")
        #expect(model.hasQuery)
    }

    @Test func notebookScopeOnlyReturnsItsPages() async throws {
        let f = try SearchFixture()
        let a = try f.notebook("A", pages: 2)
        let b = try f.notebook("B")
        try f.pages(of: a)[1].recognizedText = "shared word"
        try f.pages(of: b)[0].recognizedText = "shared word"
        try f.services.context.save()
        await f.service.refreshIndex()

        let model = SearchResultsModel(service: f.service, notebookID: a.id)
        model.update(query: "shared")
        #expect(model.titles.isEmpty)
        #expect(model.pages.map(\.pageNumber) == [2])
    }

    @Test func blankQueryClearsResults() async throws {
        let f = try SearchFixture()
        try f.notebook("Anything")
        await f.service.refreshIndex()
        let model = SearchResultsModel(service: f.service)
        model.update(query: "any")
        #expect(!model.isEmpty)
        model.update(query: "  ?! ")
        #expect(model.isEmpty)
        #expect(!model.hasQuery)
    }
}

@Suite struct SnippetTextTests {
    @Test func marksMatchesAndIgnoresBadRanges() {
        let snippet = SearchSnippet(text: "buy milk now", ranges: [4..<8, 50..<60, 3..<3])
        let text = SnippetText.attributed(snippet)
        #expect(String(text.characters) == "buy milk now")
        let marked = text.runs.filter { $0.backgroundColor != nil }.map { String(text[$0.range].characters) }
        #expect(marked == ["milk"])
    }
}
