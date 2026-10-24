import Foundation
import SwiftData

public struct DeckSummary: Identifiable, Equatable, Sendable {
    public var name: String
    public var total: Int
    public var due: Int
    public var id: String { name }
}

public extension StudyState {
    var schedule: SM2Schedule {
        SM2Schedule(ease: ease, intervalDays: intervalDays, repetitions: repetitions, lapses: lapses)
    }

    var isNew: Bool { lastReviewedAt == nil }

    /// Applies one review and marks the record for sync.
    func apply(grade: SM2Grade, at now: Date, calendar: Calendar = .current) {
        let r = SM2Scheduler.review(schedule, grade: grade, at: now, calendar: calendar)
        ease = r.schedule.ease
        intervalDays = r.schedule.intervalDays
        repetitions = r.schedule.repetitions
        lapses = r.schedule.lapses
        dueAt = r.dueAt
        lastReviewedAt = now
        markDirty(self, fields: ["ease", "intervalDays", "repetitions", "lapses", "dueAt", "lastReviewedAt"], now: now)
    }
}

/// Flashcards and their review state. Cards are never hard-deleted here: "delete" is a soft delete that sync and
/// the 30-day purge handle like every other record.
@MainActor
public final class StudyStore {
    public static let defaultDeck = "General"
    private let context: ModelContext

    public init(context: ModelContext) { self.context = context }

    // MARK: Reading

    public func cards(in notebookID: UUID, deck: String? = nil) throws -> [Flashcard] {
        let all = try context.fetch(FetchDescriptor<Flashcard>(
            predicate: #Predicate { $0.notebookID == notebookID && $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.createdAt), SortDescriptor(\.id)]))
        guard let deck else { return all }
        return all.filter { $0.deck == deck }
    }

    public func state(for flashcardID: UUID) throws -> StudyState? {
        try context.fetch(FetchDescriptor<StudyState>(
            predicate: #Predicate { $0.flashcardID == flashcardID && $0.deletedAt == nil })).first
    }

    public func decks(in notebookID: UUID, now: Date = .now) throws -> [DeckSummary] {
        let cards = try cards(in: notebookID)
        let dueIDs = Set(try dueCardIDs(in: notebookID, deck: nil, now: now))
        var totals: [String: (total: Int, due: Int)] = [:]
        for card in cards {
            var t = totals[card.deck] ?? (0, 0)
            t.total += 1
            if dueIDs.contains(card.id) { t.due += 1 }
            totals[card.deck] = t
        }
        return totals.map { DeckSummary(name: $0.key, total: $0.value.total, due: $0.value.due) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public func dueCardIDs(in notebookID: UUID, deck: String?, now: Date = .now, limit: Int? = nil) throws -> [UUID] {
        let cards = try cards(in: notebookID, deck: deck)
        let states = try context.fetch(FetchDescriptor<StudyState>(predicate: #Predicate { $0.deletedAt == nil }))
        let byCard = Dictionary(states.map { ($0.flashcardID, $0) }, uniquingKeysWith: { a, _ in a })
        let items = cards.map { card -> StudyQueueItem in
            let s = byCard[card.id]
            return StudyQueueItem(id: card.id, dueAt: s?.dueAt ?? card.createdAt, isNew: s?.isNew ?? true)
        }
        return StudyQueue.due(items, now: now, limit: limit)
    }

    public func dueCards(in notebookID: UUID, deck: String?, now: Date = .now, limit: Int? = nil) throws -> [Flashcard] {
        let ids = try dueCardIDs(in: notebookID, deck: deck, now: now, limit: limit)
        let byID = Dictionary(try cards(in: notebookID).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return ids.compactMap { byID[$0] }
    }

    // MARK: Writing

    @discardableResult
    public func createCard(notebookID: UUID, deck: String, sourcePageID: UUID?, frontImage: Data, backImage: Data,
                           now: Date = .now) throws -> Flashcard {
        guard !frontImage.isEmpty, !backImage.isEmpty else {
            throw StoreError.invalid("A flashcard needs both a front and a back.")
        }
        let name = deck.trimmingCharacters(in: .whitespacesAndNewlines)
        let card = Flashcard(notebookID: notebookID, deck: name.isEmpty ? Self.defaultDeck : name,
                             sourcePageID: sourcePageID, frontImage: frontImage, backImage: backImage, now: now)
        let state = StudyState(flashcardID: card.id, dueAt: now, now: now)
        context.insert(card)
        context.insert(state)
        markDirty(card, fields: ["notebookID", "deck", "sourcePageID", "frontImage", "backImage"], now: now)
        markDirty(state, fields: ["flashcardID", "ease", "intervalDays", "repetitions", "lapses", "dueAt"], now: now)
        try context.save()
        return card
    }

    @discardableResult
    public func review(cardID: UUID, grade: SM2Grade, now: Date = .now, calendar: Calendar = .current) throws -> StudyState {
        guard let state = try state(for: cardID) else { throw StoreError.notFound("the flashcard's study progress") }
        state.apply(grade: grade, at: now, calendar: calendar)
        try context.save()
        return state
    }

    public func moveCard(_ cardID: UUID, toDeck deck: String, now: Date = .now) throws {
        guard let card = try fetchCard(cardID) else { throw StoreError.notFound("the flashcard") }
        let name = deck.trimmingCharacters(in: .whitespacesAndNewlines)
        card.deck = name.isEmpty ? Self.defaultDeck : name
        markDirty(card, fields: ["deck"], now: now)
        try context.save()
    }

    public func renameDeck(_ old: String, to new: String, in notebookID: UUID, now: Date = .now) throws {
        let name = new.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw StoreError.invalid("A deck needs a name.") }
        for card in try cards(in: notebookID, deck: old) {
            card.deck = name
            markDirty(card, fields: ["deck"], now: now)
        }
        try context.save()
    }

    /// Soft delete: the card and its study progress get a `deletedAt` and stay recoverable until the purge.
    public func softDelete(cardID: UUID, now: Date = .now) throws {
        guard let card = try fetchCard(cardID) else { throw StoreError.notFound("the flashcard") }
        card.deletedAt = now
        markDirty(card, fields: ["deletedAt"], now: now)
        if let state = try state(for: cardID) {
            state.deletedAt = now
            markDirty(state, fields: ["deletedAt"], now: now)
        }
        try context.save()
    }

    private func fetchCard(_ id: UUID) throws -> Flashcard? {
        try context.fetch(FetchDescriptor<Flashcard>(predicate: #Predicate { $0.id == id && $0.deletedAt == nil })).first
    }
}
