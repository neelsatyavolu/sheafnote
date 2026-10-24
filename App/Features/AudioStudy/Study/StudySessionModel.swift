import Foundation
import Observation
import SheafnoteCore

/// One pass through the due cards of a deck. The queue is fixed when the session starts; a card graded "again"
/// is rescheduled for tomorrow by the scheduler and does not come back in this pass.
@MainActor @Observable
final class StudySessionModel {
    private(set) var cards: [Flashcard]
    private(set) var index = 0
    private(set) var isRevealed = false
    private(set) var reviewed = 0
    private(set) var againCount = 0
    private(set) var errorMessage: String?

    private let store: StudyStore
    private let now: @MainActor () -> Date

    init(cards: [Flashcard], store: StudyStore, now: @escaping @MainActor () -> Date = { Date() }) {
        self.cards = cards
        self.store = store
        self.now = now
    }

    var current: Flashcard? { cards.indices.contains(index) ? cards[index] : nil }
    var isFinished: Bool { current == nil }
    var total: Int { cards.count }

    func reveal() { isRevealed = true }

    /// Labels under the grade buttons, e.g. "1d", "6d".
    var nextIntervals: [SM2Grade: String] {
        guard let current, let state = try? store.state(for: current.id) else { return [:] }
        return SM2Scheduler.nextIntervals(for: state.schedule).mapValues { SM2Scheduler.intervalLabel(days: $0) }
    }

    /// Saves the review, then moves on. If saving fails the card stays up and the error is shown.
    func grade(_ grade: SM2Grade) {
        guard let card = current, isRevealed else { return }
        do {
            try store.review(cardID: card.id, grade: grade, now: now())
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        errorMessage = nil
        reviewed += 1
        if !grade.isPassing { againCount += 1 }
        index += 1
        isRevealed = false
    }
}
