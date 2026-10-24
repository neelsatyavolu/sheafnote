import Foundation
import SwiftData
@testable import SheafnoteCore

/// Ink codec for tests: the "drawing" is JSON of stroke entries, merged with the real `StrokeMerger`.
struct JSONInkMerging: InkMerging {
    struct Item: Codable { var id: String; var t: Double }

    static func data(_ items: [(String, Double)]) -> Data {
        // Encoding plain Codable values cannot fail.
        (try? JSONEncoder().encode(items.map { Item(id: $0.0, t: $0.1) })) ?? Data()
    }

    static func ids(_ items: [(String, Double)]) -> [String] { items.map(\.0) }

    func merge(baseStrokeIDs: [String], ours: InkState, theirs: InkState) throws -> InkState {
        let o = try decode(ours, side: "your")
        let t = try decode(theirs, side: "iCloud")
        let base = baseStrokeIDs.map { StrokeEntry(id: StrokeID(rawValue: $0), creationDate: .distantPast) }
        let result = StrokeMerger.merge(base: base, ours: o.map(entry), theirs: t.map(entry))
        let byID = Dictionary((o + t).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let items = result.ordered.compactMap { byID[$0.id.rawValue] }
        return InkState(data: try JSONEncoder().encode(items), strokeIDs: items.map(\.id))
    }

    private func entry(_ i: Item) -> StrokeEntry {
        StrokeEntry(id: StrokeID(rawValue: i.id), creationDate: Date(timeIntervalSinceReferenceDate: i.t))
    }

    private func decode(_ s: InkState, side: String) throws -> [Item] {
        guard let data = s.data else { return [] }
        do { return try JSONDecoder().decode([Item].self, from: data) } catch { throw InkMergeError.undecodable(side: side) }
    }
}

@MainActor
struct SyncFixture {
    let store: StoreFixture
    var context: ModelContext { store.context }

    init() throws { store = try StoreFixture() }

    /// A page with ink that has been "synced": clean, with a base.
    func syncedPage(strokes: [(String, Double)], in notebook: Notebook? = nil) throws -> Page {
        let nb = try notebook ?? store.notebook()
        let page = try store.pages.addPage(to: nb.id, at: .end, template: nil)
        page.inkData = JSONInkMerging.data(strokes)
        page.strokeIDs = JSONInkMerging.ids(strokes)
        page.inkHash = Hashing.sha256Hex(page.inkData ?? Data())
        page.adoptServerInkAsBase()
        page.syncDirty = false
        page.dirtyFields = []
        try context.save()
        return page
    }

    func edit(_ page: Page, strokes: [(String, Double)]) throws {
        page.inkData = JSONInkMerging.data(strokes)
        page.strokeIDs = JSONInkMerging.ids(strokes)
        page.inkHash = Hashing.sha256Hex(page.inkData ?? Data())
        markDirty(page, fields: ["inkData", "strokeIDs", "inkHash"])
        try context.save()
    }

    /// One row of every synced type with non-default values.
    func populateEverything() throws -> [RecordKey] {
        let nb = try store.notebook("Physics")
        nb.isFavorite = true
        nb.richText = Data([9, 9])
        try store.library.createFolder(name: "School", in: nil)
        let page = try syncedPage(strokes: [("a", 1), ("b", 2)], in: nb)
        page.recognizedText = "hello"
        page.backgroundPageIndex = 3
        let element = PageElement(value: ElementValue(pageID: page.id, kind: .sticker, frame: CGRect(x: 1, y: 2, width: 3, height: 4),
                                                      rotation: 0.5, zIndex: 2, payload: Data([1]), assetID: UUID()))
        let asset = Asset(kind: .pdf, data: Data(repeating: 7, count: 300_000), sha256: "abc", filename: "a.pdf", uti: "com.adobe.pdf")
        let outline = OutlineEntry(notebookID: nb.id, title: "Intro", pageID: page.id, pdfPageIndex: 4, parentID: nil, sortKey: "m")
        let bookmark = Bookmark(notebookID: nb.id, pageID: page.id, title: "Mark")
        let audio = AudioRecording(notebookID: nb.id, assetID: asset.id, title: "Lecture",
                                   startedAt: Date(timeIntervalSinceReferenceDate: 500), duration: 12.5, timeline: Data([4]))
        let card = Flashcard(notebookID: nb.id, deck: "d", sourcePageID: page.id, frontImage: Data([1]), backImage: Data([2]),
                             frontText: "q", backText: "a")
        let study = StudyState(flashcardID: card.id, dueAt: Date(timeIntervalSinceReferenceDate: 900))
        study.ease = 2.1; study.intervalDays = 6; study.repetitions = 3; study.lapses = 1
        study.lastReviewedAt = Date(timeIntervalSinceReferenceDate: 800)
        let saved = SavedElement(name: "Arrow", category: "shapes", width: 10, height: 20, inkData: Data([5]),
                                 elements: Data([6]), thumbnail: Data([7]))
        let setting = AppSetting(id: AppSettingsStore.settingID(for: "k"), key: "k", valueJSON: Data([1, 2]))
        context.insert(element); context.insert(asset); context.insert(outline); context.insert(bookmark); context.insert(audio)
        context.insert(card); context.insert(study); context.insert(saved); context.insert(setting)
        try context.save()
        return try RecordMapper.allKeys(in: context)
    }
}
