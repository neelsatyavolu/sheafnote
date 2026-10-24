import PencilKit
import SwiftUI
import Testing
import UIKit
import SheafnoteCore
@testable import Sheafnote

/// Element store over an array, standing in for the editor's page.
@MainActor
final class SearchFakeElementStore: PageElementStore {
    var all: [ElementValue] = []
    private(set) var undoNames: [String] = []

    @discardableResult
    func add(_ element: ElementValue, undoName: LocalizedStringResource) throws -> ElementValue {
        all.append(element)
        undoNames.append(String(localized: undoName))
        return element
    }

    func update(id: UUID, undoName: LocalizedStringResource, _ mutate: (inout ElementValue) -> Void) throws {
        guard let i = all.firstIndex(where: { $0.id == id }) else { return }
        mutate(&all[i])
        undoNames.append(String(localized: undoName))
    }

    func remove(ids: Set<UUID>, undoName: LocalizedStringResource) throws { all.removeAll { ids.contains($0.id) } }
}

@MainActor
final class SearchFakeInk: PageInkAccess {
    var strokes: [IdentifiedStroke] = []
    var lastInkTouchDate: Date?
    func edit(_ name: LocalizedStringResource, _ body: (inout [PKStroke]) -> Void) {}
    func strokes(intersecting polygon: [CGPoint]) -> [IdentifiedStroke] { [] }
    func render(strokeIDs: Set<StrokeID>, scale: CGFloat) -> UIImage? { nil }
}

@MainActor
final class SearchFakePage: PageContext {
    let notebookID: UUID
    let pageID = UUID()
    let pageSize = CGSize(width: 600, height: 800)
    let zoomScale: CGFloat = 1
    let ink: any PageInkAccess = SearchFakeInk()
    let store = SearchFakeElementStore()
    var elements: any PageElementStore { store }
    let undoManager = UndoManager()

    init(notebookID: UUID = UUID()) { self.notebookID = notebookID }

    func pageToScreen(_ rect: CGRect) -> CGRect { rect }
    func screenToPage(_ point: CGPoint) -> CGPoint { point }
}

@MainActor
@Suite struct LinkToSelectionTests {
    private let choice = LinkChoice(target: .url(URL(string: "https://example.com")!), label: "example.com")

    @Test func inkSelectionGetsALinkElementOverItsBounds() throws {
        let page = SearchFakePage()
        let bounds = CGRect(x: 100, y: 200, width: 80, height: 30)
        try LinkToSelectionAction.apply(choice, strokeCount: 3, elementIDs: [], bounds: bounds, page: page)
        let link = try #require(page.store.all.first)
        #expect(link.kind == .link)
        #expect(link.frame == bounds.insetBy(dx: -4, dy: -4))
        let payload = try #require(PayloadCodec.decode(LinkPayload.self, from: link.payload))
        #expect(payload.target == choice.target)
        #expect(payload.label == "example.com")
    }

    @Test func linkElementsStackAboveExistingOnes() throws {
        let page = SearchFakePage()
        page.store.all = [ElementValue(pageID: page.pageID, kind: .image, frame: .zero, zIndex: 5)]
        try LinkToSelectionAction.apply(choice, strokeCount: 1, elementIDs: [], bounds: CGRect(x: 0, y: 0, width: 10, height: 10), page: page)
        #expect(page.store.all.last?.zIndex == 6)
    }

    @Test func aSelectedTextBoxKeepsTheLinkInItsPayload() throws {
        let page = SearchFakePage()
        let text = ElementValue(pageID: page.pageID, kind: .text, frame: CGRect(x: 10, y: 10, width: 100, height: 30),
                                payload: PayloadCodec.encode(TextPayload(text: "see chapter 2")))
        page.store.all = [text]
        try LinkToSelectionAction.apply(choice, strokeCount: 0, elementIDs: [text.id], bounds: text.frame, page: page)
        #expect(page.store.all.count == 1)
        let payload = try #require(PayloadCodec.decode(TextPayload.self, from: page.store.all[0].payload))
        #expect(payload.link == choice.target)
        #expect(payload.text == "see chapter 2")
    }

    @Test func aSelectedLinkIsRetargetedNotDuplicated() throws {
        let page = SearchFakePage()
        let old = ElementValue(pageID: page.pageID, kind: .link, frame: CGRect(x: 0, y: 0, width: 50, height: 20),
                               payload: PayloadCodec.encode(LinkPayload(target: .page(UUID()), label: "Page 1")))
        page.store.all = [old]
        try LinkToSelectionAction.apply(choice, strokeCount: 0, elementIDs: [old.id], bounds: old.frame, page: page)
        #expect(page.store.all.count == 1)
        #expect(PayloadCodec.decode(LinkPayload.self, from: page.store.all[0].payload)?.target == choice.target)
    }

    @Test func emptyBoundsAreRejectedWithAFriendlyError() {
        let page = SearchFakePage()
        #expect(throws: LinkError.self) {
            try LinkToSelectionAction.apply(choice, strokeCount: 1, elementIDs: [], bounds: nil, page: page)
        }
        #expect(page.store.all.isEmpty)
    }

    @Test func actionIsOnlyEnabledWithASelection() throws {
        let action = LinkToSelectionAction()
        let selection = SelectionModel()
        let f = try EditorFixture()
        #expect(!action.isEnabled(for: selection, editor: f.session))
        selection.select(pageID: UUID(), strokeIDs: [StrokeID(rawValue: "a")], elementIDs: [], bounds: CGRect(x: 0, y: 0, width: 5, height: 5))
        #expect(action.isEnabled(for: selection, editor: f.session))
    }
}

@MainActor
@Suite struct LinkFollowerTests {
    @Test func missingPageAndNotebookReportAFriendlyFailure() async throws {
        let f = try SearchFixture()
        let host = FeatureHost(services: f.services)
        let page = await LinkFollower.follow(.page(UUID()), from: UUID(), host: host)
        guard case .failed = page else { Issue.record("expected a failure for a missing page"); return }
        let notebook = await LinkFollower.follow(.notebook(UUID()), from: UUID(), host: host)
        guard case .failed = notebook else { Issue.record("expected a failure for a missing notebook"); return }
    }

    @Test func deletedPageCountsAsMissing() async throws {
        let f = try SearchFixture()
        let nb = try f.notebook("N", pages: 2)
        let victim = try f.pages(of: nb)[1]
        try f.services.pages.softDelete(pageIDs: [victim.id])
        let outcome = await LinkFollower.follow(.page(victim.id), from: nb.id, host: FeatureHost(services: f.services))
        guard case .failed = outcome else { Issue.record("expected a failure"); return }
    }

    @Test func linkInTheSameNotebookScrollsThatEditor() async throws {
        let fixture = try EditorFixture(pages: 3)
        EditorTabs.shared.open(fixture.notebook)
        defer { EditorTabs.shared.closeAll() }
        _ = EditorTabs.shared.session(for: fixture.notebook, host: fixture.host, sizing: .fixed(.zero))
        let target = fixture.session.pageIDs[2]
        let outcome = await LinkFollower.follow(.page(target), from: fixture.notebook.id, host: fixture.host)
        guard case .done = outcome else { Issue.record("expected the link to be followed"); return }
        let session = EditorTabs.shared.session(for: fixture.notebook, host: fixture.host, sizing: .fixed(.zero))
        #expect(session.currentPageID == target)
    }
}
