import Foundation
import PencilKit
import SwiftData
import Testing
import SheafnoteCore
@testable import Sheafnote

@MainActor
struct AudioStudySessionTests {
    let fx: EditorFixture
    let capture = FakeAudioCapture()
    let player = FakeAudioPlayer()
    let session: AudioStudySession

    init() throws {
        fx = try EditorFixture()
        AudioStudyFeature.register(into: fx.host)
        session = AudioStudySession(notebookID: fx.notebook.id, services: fx.services, capture: capture, player: player,
                                    pendingDirectory: audioTemporaryDirectory())
        session.editor = fx.session
    }

    @Test func featureRegistersToolMenusSettingsAndSelectionAction() {
        #expect(fx.host.tools.tool(PlaybackTool.toolID) != nil)
        #expect(fx.host.settings.sections.contains { $0.id == "audio" && $0.order == 60 })
        #expect(fx.host.selectionActions.actions.contains { $0.id == "audio.makeFlashcard" })
        let menu = fx.host.notebookMenu
        #expect(menu.menuItems.contains { $0.id == "audio.record" && $0.group == .tools })
        #expect(menu.barItems.contains { $0.id == "audio.bar" && !$0.slot.isLeading })
        #expect(menu.pageMenuItems.contains { $0.id == "audio.flashcards" })
        #expect(menu.navigatorTabs.contains { $0.id == "audio.flashcards" })
    }

    @Test func toggleRecordingStartsThenSavesAndListsTheRecording() async {
        await session.toggleRecording()
        #expect(session.recorder.isRecording)
        await session.toggleRecording()
        #expect(session.items.count == 1)
        #expect(session.items[0].title == "Recording 1")
    }

    @Test func renameAndSoftDeleteUpdateTheList() async throws {
        await session.toggleRecording()
        await session.toggleRecording()
        let rec = try #require(session.items.first)
        session.rename(rec, to: "Lecture 1")
        #expect(session.items.first?.title == "Lecture 1")
        session.rename(rec, to: "  ")
        #expect(session.errorMessage != nil)
        #expect(session.items.first?.title == "Lecture 1")
        session.dismissError()
        session.delete(rec)
        #expect(session.items.isEmpty)
        let rows = try fx.services.context.fetch(FetchDescriptor<AudioRecording>())
        #expect(rows.count == 1 && rows[0].deletedAt != nil, "soft delete keeps the row")
    }

    @Test func playbackSwitchesToThePlaybackToolAndRestoresThePreviousOne() async throws {
        await session.toggleRecording()
        await session.toggleRecording()
        let rec = try #require(session.items.first)
        fx.session.toolState.select(.highlighter)
        session.beginPlayback(rec)
        #expect(fx.session.toolState.activeToolID == PlaybackTool.toolID)
        #expect(session.player.isPlaying)
        session.endPlayback()
        #expect(fx.session.toolState.activeToolID == .highlighter)
        #expect(!session.player.isLoaded)
    }

    @Test func deletingTheRecordingThatIsPlayingStopsPlayback() async throws {
        await session.toggleRecording()
        await session.toggleRecording()
        let rec = try #require(session.items.first)
        session.beginPlayback(rec)
        session.delete(rec)
        #expect(!session.player.isLoaded)
        #expect(fx.session.toolState.activeToolID != PlaybackTool.toolID)
    }

    @Test func playbackFailureIsShownAndToolIsNotSwitched() async throws {
        await session.toggleRecording()
        await session.toggleRecording()
        let rec = try #require(session.items.first)
        player.loadError = PlaybackError.unreadable
        session.beginPlayback(rec)
        #expect(session.errorMessage != nil)
        #expect(fx.session.toolState.activeToolID != PlaybackTool.toolID)
    }

    @Test func timedStrokesComeFromThePageInk() throws {
        let page = try fx.page()
        let date = Date(timeIntervalSinceReferenceDate: 5_000)
        page.setDrawing(PKDrawing(strokes: [TestInk.stroke(from: .zero, to: CGPoint(x: 50, y: 50), date: date)]), undoName: "t")
        let timed = session.timedStrokes(onPage: fx.firstPageID)
        #expect(timed.count == 1)
        #expect(timed[0].creationDate == date)
    }

    @Test func makingAFlashcardCutsTwoRegionsFromThePage() async throws {
        let size = try #require(fx.services.pages.page(id: fx.firstPageID)?.size)
        let maker = FlashcardMaker(editor: fx.session, pageID: fx.firstPageID, pageSize: size,
                                   selection: CGRect(x: 60, y: 60, width: 200, height: 80), deck: "Bio")
        let saved = await maker.save()
        #expect(saved, Comment(rawValue: maker.errorMessage ?? "no error"))
        let cards = try session.study.cards(in: fx.notebook.id, deck: "Bio")
        #expect(cards.count == 1)
        #expect(cards[0].sourcePageID == fx.firstPageID)
        #expect(UIImage(data: cards[0].frontImage) != nil && UIImage(data: cards[0].backImage) != nil)
    }
}
