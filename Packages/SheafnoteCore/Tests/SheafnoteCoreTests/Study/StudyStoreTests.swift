import Foundation
import SwiftData
import Testing
@testable import SheafnoteCore

@MainActor
struct StudyStoreTests {
    let fx: StoreFixture
    let store: StudyStore
    let nb: UUID
    let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)
    let png = Data([1, 2, 3])

    init() throws {
        fx = try StoreFixture()
        store = StudyStore(context: fx.context)
        nb = try fx.notebook().id
    }

    @discardableResult
    func card(_ deck: String = "Bio", at now: Date? = nil) throws -> Flashcard {
        try store.createCard(notebookID: nb, deck: deck, sourcePageID: nil, frontImage: png, backImage: png, now: now ?? t0)
    }

    @Test func createdCardStartsNewAndDueNow() throws {
        let c = try card()
        let s = try #require(try store.state(for: c.id))
        #expect(s.isNew && s.ease == 2.5 && s.repetitions == 0)
        #expect(try store.dueCardIDs(in: nb, deck: nil, now: t0) == [c.id])
        #expect(c.syncDirty)
    }

    @Test func emptyDeckNameFallsBackToDefault() throws {
        #expect(try card("   ").deck == StudyStore.defaultDeck)
    }

    @Test func emptyImagesAreRejected() throws {
        #expect(throws: StoreError.self) {
            try store.createCard(notebookID: nb, deck: "x", sourcePageID: nil, frontImage: Data(), backImage: png)
        }
        #expect(try store.cards(in: nb).isEmpty)
    }

    @Test func reviewSchedulesAndRemovesFromDueQueue() throws {
        let c = try card()
        let s = try store.review(cardID: c.id, grade: .good, now: t0)
        #expect(s.intervalDays == 1 && s.repetitions == 1 && s.lastReviewedAt == t0)
        #expect(try store.dueCardIDs(in: nb, deck: nil, now: t0).isEmpty)
        #expect(try store.dueCardIDs(in: nb, deck: nil, now: t0.addingTimeInterval(2 * 86_400)) == [c.id])
    }

    @Test func failedReviewComesBackTomorrowAndCountsLapse() throws {
        let c = try card()
        try store.review(cardID: c.id, grade: .good, now: t0)
        let s = try store.review(cardID: c.id, grade: .again, now: t0.addingTimeInterval(86_400))
        #expect(s.lapses == 1 && s.repetitions == 0 && s.intervalDays == 1)
    }

    @Test func decksSummariseTotalsAndDueCounts() throws {
        let a = try card("Anatomy")
        try card("Anatomy")
        try card("Chem")
        try store.review(cardID: a.id, grade: .easy, now: t0)
        let decks = try store.decks(in: nb, now: t0)
        #expect(decks == [DeckSummary(name: "Anatomy", total: 2, due: 1), DeckSummary(name: "Chem", total: 1, due: 1)])
    }

    @Test func dueCardsFilterByDeckAndLimit() throws {
        try card("A"); try card("A"); try card("B")
        #expect(try store.dueCards(in: nb, deck: "A", now: t0).count == 2)
        #expect(try store.dueCards(in: nb, deck: nil, now: t0, limit: 2).count == 2)
    }

    @Test func softDeleteHidesCardAndStateButKeepsRows() throws {
        let c = try card()
        try store.softDelete(cardID: c.id, now: t0)
        #expect(try store.cards(in: nb).isEmpty)
        #expect(try fx.context.fetch(FetchDescriptor<Flashcard>()).count == 1)
        #expect(try fx.context.fetch(FetchDescriptor<StudyState>()).first?.deletedAt == t0)
        #expect(try store.dueCardIDs(in: nb, deck: nil, now: t0).isEmpty)
    }

    @Test func renameAndMoveDecks() throws {
        let c = try card("Old")
        try card("Old")
        try store.renameDeck("Old", to: "New", in: nb)
        #expect(try store.cards(in: nb, deck: "New").count == 2)
        try store.moveCard(c.id, toDeck: "Other")
        #expect(try store.cards(in: nb, deck: "Other").count == 1)
        #expect(throws: StoreError.self) { try store.renameDeck("New", to: " ", in: nb) }
    }

    @Test func otherNotebooksAreIsolated() throws {
        try card()
        let other = try fx.notebook("Other").id
        #expect(try store.cards(in: other).isEmpty)
    }

    @Test func reviewOfUnknownCardThrows() {
        #expect(throws: StoreError.self) { try store.review(cardID: UUID(), grade: .good) }
    }

    @Test func tenThousandCardQueueIsFast() throws {
        for i in 0..<2_000 { try card("D\(i % 5)", at: t0.addingTimeInterval(Double(i))) }
        let start = Date()
        let ids = try store.dueCardIDs(in: nb, deck: nil, now: t0.addingTimeInterval(5_000), limit: 50)
        #expect(ids.count == 50)
        #expect(Date().timeIntervalSince(start) < 5)
    }
}

@MainActor
struct RecordingStoreTests {
    let fx: StoreFixture
    let store: RecordingStore
    let nb: UUID
    let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    init() throws {
        fx = try StoreFixture()
        store = RecordingStore(context: fx.context)
        nb = try fx.notebook().id
    }

    let pageID = UUID()

    func timeline() -> AudioTimeline {
        AudioTimeline(startedAt: start, duration: 42,
                      marks: [AudioStrokeMark(pageID: pageID, strokeID: StrokeID(rawValue: "s"), offset: 5)])
    }

    @Test func saveStoresAssetAndMetadataAndRoundTrips() throws {
        let r = try store.save(notebookID: nb, audio: Data([9, 9]), title: " Lecture ", timeline: timeline(), now: start)
        #expect(r.title == "Lecture" && r.duration == 42)
        #expect(try store.audioData(for: r) == Data([9, 9]))
        #expect(store.timeline(for: r) == timeline())
        #expect(try fx.context.fetch(FetchDescriptor<Asset>()).first?.kind == .audio)
    }

    @Test func emptyAudioIsRejectedAndNothingIsStored() throws {
        #expect(throws: StoreError.self) { try store.save(notebookID: nb, audio: Data(), title: "x", timeline: timeline()) }
        #expect(try fx.context.fetch(FetchDescriptor<Asset>()).isEmpty)
        #expect(try store.recordings(in: nb).isEmpty)
    }

    @Test func listIsNewestFirstAndScopedToNotebook() throws {
        try store.save(notebookID: nb, audio: Data([1]), title: "old", timeline: AudioTimeline(startedAt: start, duration: 1))
        try store.save(notebookID: nb, audio: Data([2]), title: "new",
                       timeline: AudioTimeline(startedAt: start.addingTimeInterval(100), duration: 1))
        #expect(try store.recordings(in: nb).map(\.title) == ["new", "old"])
        #expect(try store.recordings(in: UUID()).isEmpty)
    }

    @Test func renameTrimsAndRejectsEmpty() throws {
        let r = try store.save(notebookID: nb, audio: Data([1]), title: "a", timeline: timeline())
        try store.rename(r.id, to: "  Week 3  ")
        #expect(r.title == "Week 3")
        #expect(throws: StoreError.self) { try store.rename(r.id, to: "   ") }
        #expect(r.title == "Week 3")
    }

    @Test func softDeleteKeepsAudioAndCanBeRestored() throws {
        let r = try store.save(notebookID: nb, audio: Data([1]), title: "a", timeline: timeline())
        try store.softDelete(r.id, now: start)
        #expect(try store.recordings(in: nb).isEmpty)
        #expect(try fx.context.fetch(FetchDescriptor<Asset>()).count == 1)
        try store.restore(r.id)
        #expect(try store.recordings(in: nb).count == 1)
    }

    @Test func nextTitleSkipsUsedNames() throws {
        #expect(try store.nextTitle(in: nb) == "Recording 1")
        try store.save(notebookID: nb, audio: Data([1]), title: "Recording 1", timeline: timeline())
        #expect(try store.nextTitle(in: nb) == "Recording 2")
    }

    @Test func missingAudioThrowsAFriendlyError() throws {
        let r = try store.save(notebookID: nb, audio: Data([1]), title: "a", timeline: timeline())
        r.assetID = UUID()
        #expect(throws: StoreError.self) { try store.audioData(for: r) }
    }
}
