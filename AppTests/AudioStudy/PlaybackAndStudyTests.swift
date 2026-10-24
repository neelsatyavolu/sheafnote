import Foundation
import PencilKit
import Testing
import SheafnoteCore
@testable import Sheafnote

@MainActor
struct PlaybackControllerTests {
    let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
    let player = FakeAudioPlayer()
    let controller: PlaybackController
    let recording: AudioRecording

    init() {
        controller = PlaybackController(player: player)
        recording = AudioRecording(notebookID: UUID(), assetID: UUID(), title: "t", startedAt: Date(timeIntervalSinceReferenceDate: 800_000_000), duration: 60)
    }

    func load() {
        controller.load(recording, audio: Data([1]), timeline: AudioTimeline(startedAt: start, duration: 60))
    }

    func stroke(_ name: String, at offset: Double) -> TimedStroke {
        TimedStroke(id: StrokeID(rawValue: name), creationDate: start.addingTimeInterval(offset))
    }

    @Test func tappingAStrokeSeeksToWhenItWasWrittenAndPlays() {
        load()
        #expect(controller.seek(toStroke: stroke("a", at: 25)))
        #expect(player.currentTime == 25)
        #expect(controller.currentTime == 25)
        #expect(controller.isPlaying && player.isPlaying)
    }

    @Test func strokeOutsideTheRecordingDoesNotMovePlayhead() {
        load()
        player.currentTime = 10
        #expect(!controller.seek(toStroke: stroke("early", at: -400)))
        #expect(player.currentTime == 10)
        #expect(!controller.isPlaying)
    }

    @Test func seekNeedsALoadedRecording() {
        #expect(!controller.seek(toStroke: stroke("a", at: 1)))
    }

    @Test func seekClampsToTheAudioLength() {
        load()
        controller.seek(to: 9_999)
        #expect(controller.currentTime == 60)
        controller.seek(to: -5)
        #expect(controller.currentTime == 0)
    }

    @Test func strokesAfterThePlayheadAreDimmed() {
        load()
        let strokes = [stroke("a", at: 5), stroke("b", at: 30), stroke("c", at: 50)]
        controller.seek(to: 30)
        #expect(controller.dimmedStrokeIDs(among: strokes) == [StrokeID(rawValue: "c")])
        controller.seek(to: 0)
        #expect(controller.dimmedStrokeIDs(among: strokes).count == 3)
    }

    @Test func nothingIsDimmedWithoutARecording() {
        #expect(controller.dimmedStrokeIDs(among: [stroke("a", at: 5)]).isEmpty)
    }

    @Test func unreadableAudioShowsAMessageAndStaysUnloaded() {
        player.loadError = PlaybackError.unreadable
        load()
        #expect(!controller.isLoaded)
        #expect(controller.errorMessage != nil)
    }

    @Test func playAfterTheEndRestartsFromTheBeginning() {
        load()
        controller.seek(to: 60)
        controller.play()
        #expect(player.currentTime == 0)
    }

    @Test func finishingStopsPlayingAndParksAtTheEnd() {
        load()
        controller.play()
        player.onFinished?()
        #expect(!controller.isPlaying)
        #expect(controller.currentTime == controller.duration)
    }

    @Test func skipMovesRelativeToThePlayhead() {
        load()
        controller.seek(to: 20)
        controller.skip(by: -10)
        #expect(controller.currentTime == 10)
    }

    @Test func pencilKitStrokesCarryCreationDatesIntoTheTimeline() {
        let date = start.addingTimeInterval(12)
        let points = [PKStrokePoint(location: .zero, timeOffset: 0, size: CGSize(width: 3, height: 3), opacity: 1, force: 1, azimuth: 0, altitude: 1),
                      PKStrokePoint(location: CGPoint(x: 10, y: 0), timeOffset: 0.1, size: CGSize(width: 3, height: 3), opacity: 1, force: 1, azimuth: 0, altitude: 1)]
        let pk = PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: points, creationDate: date))
        let timed = AudioStudySession.timed([IdentifiedStroke(id: StrokeID(rawValue: "x"), stroke: pk)])
        #expect(timed.first?.creationDate == date)
        #expect(pk.sampledPoints().count >= 2)
    }
}

@MainActor
struct StudySessionModelTests {
    let services: AppServices
    let store: StudyStore
    let notebookID: UUID
    let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

    init() throws {
        services = try AppServices.inMemory()
        store = StudyStore(context: services.context)
        notebookID = try services.library.createNotebook(
            title: "N", kind: .paged, cover: .default, template: .blank, paperSize: .a4,
            orientation: .portrait, paperColor: .white, in: nil).id
    }

    func makeCards(_ n: Int) throws -> [Flashcard] {
        try (0..<n).map { _ in
            try store.createCard(notebookID: notebookID, deck: "D", sourcePageID: nil, frontImage: Data([1]), backImage: Data([2]), now: t0)
        }
    }

    @Test func gradingNeedsTheAnswerRevealedFirst() throws {
        let model = StudySessionModel(cards: try makeCards(1), store: store, now: { t0 })
        model.grade(.good)
        #expect(model.index == 0 && model.reviewed == 0)
        model.reveal()
        model.grade(.good)
        #expect(model.index == 1 && model.reviewed == 1 && model.isFinished)
    }

    @Test func gradingSchedulesTheCardAndRemovesItFromTheQueue() throws {
        let cards = try makeCards(2)
        let model = StudySessionModel(cards: cards, store: store, now: { t0 })
        model.reveal(); model.grade(.easy)
        model.reveal(); model.grade(.again)
        #expect(model.isFinished && model.againCount == 1)
        #expect(try store.dueCardIDs(in: notebookID, deck: nil, now: t0).isEmpty)
        #expect(try store.state(for: cards[1].id)?.lapses == 1)
    }

    @Test func nextIntervalLabelsComeFromTheScheduler() throws {
        let model = StudySessionModel(cards: try makeCards(1), store: store, now: { t0 })
        let labels = model.nextIntervals
        #expect(labels[.again] == "1d")
        #expect(labels[.good] == "1d")
    }

    @Test func emptyDeckIsFinishedImmediately() {
        let model = StudySessionModel(cards: [], store: store)
        #expect(model.isFinished && model.total == 0)
    }

    @Test func revealResetsAfterEachCard() throws {
        let model = StudySessionModel(cards: try makeCards(2), store: store, now: { t0 })
        model.reveal(); model.grade(.good)
        #expect(!model.isRevealed)
    }
}
