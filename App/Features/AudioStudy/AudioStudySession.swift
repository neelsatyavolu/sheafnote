import Foundation
import Observation
import PencilKit
import SheafnoteCore

/// Audio and study state for one open notebook: the recorder, the player, the recordings list.
@MainActor @Observable
final class AudioStudySession: RecordingInkSource {
    let notebookID: UUID
    let recorder: RecorderController
    let player: PlaybackController
    let recordings: RecordingStore
    let study: StudyStore
    private(set) var items: [AudioRecording] = []
    private(set) var errorMessage: String?
    @ObservationIgnored weak var editor: (any EditorContext)? { didSet { if editor != nil { hadEditor = true } } }
    @ObservationIgnored private var restoreToolID: ToolID?

    init(notebookID: UUID, services: AppServices, capture: any AudioCapturing = UITestAudio.capture(),
         player: any AudioPlaying = UITestAudio.player(), pendingDirectory: URL = AudioStudySession.pendingDirectory) {
        self.notebookID = notebookID
        let recordings = RecordingStore(context: services.context)
        self.recordings = recordings
        self.study = StudyStore(context: services.context)
        let settings = services.settings
        self.recorder = RecorderController(
            notebookID: notebookID, capture: capture, store: recordings, pendingDirectory: pendingDirectory,
            quality: { AudioSettings.quality(settings) })
        self.player = PlaybackController(player: player)
        recorder.ink = self
        recorder.onSaved = { [weak self] _ in self?.reload() }
        recorder.recoverPending()
        reload()
        watchForClosedEditor()
    }

    /// When the notebook's editor goes away, finish what was running: a recording is saved, playback stops.
    private func watchForClosedEditor() {
        Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                guard self.editor == nil, self.hadEditor else { continue }
                if self.recorder.isRecording { await self.recorder.stop(); self.reload() }
                if self.player.isLoaded { self.player.unload() }
            }
        }
    }

    @ObservationIgnored private var hadEditor = false

    static var pendingDirectory: URL {
        URL.applicationSupportDirectory.appendingPathComponent("PendingRecordings", isDirectory: true)
    }

    // MARK: Recordings list

    func reload() {
        do {
            items = try recordings.recordings(in: notebookID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func rename(_ recording: AudioRecording, to title: String) {
        perform { try recordings.rename(recording.id, to: title) }
    }

    func delete(_ recording: AudioRecording) {
        if player.recording?.id == recording.id { endPlayback() }
        perform { try recordings.softDelete(recording.id) }
    }

    func dismissError() { errorMessage = nil }

    private func perform(_ body: () throws -> Void) {
        do {
            try body()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        reload()
    }

    // MARK: Recording

    func toggleRecording() async {
        if recorder.isRecording {
            if await recorder.stop() != nil { editor?.showToast(LocalizedStringResource("Recording saved", table: "AudioStudy")) }
        } else {
            if player.isPlaying { player.pause() }
            await recorder.start()
        }
    }

    // MARK: Playback

    /// Loads the recording and switches the editor into playback mode (tap a stroke to seek).
    func beginPlayback(_ recording: AudioRecording) {
        do {
            let audio = try recordings.audioData(for: recording)
            player.load(recording, audio: audio, timeline: recordings.timeline(for: recording))
            if let message = player.errorMessage { errorMessage = message; return }
            errorMessage = nil
            enterPlaybackTool()
            player.play()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func endPlayback() {
        player.unload()
        leavePlaybackTool()
    }

    private func enterPlaybackTool() {
        guard let state = editor?.toolState else { return }
        if state.activeToolID != PlaybackTool.toolID { restoreToolID = state.activeToolID }
        state.select(PlaybackTool.toolID)
    }

    private func leavePlaybackTool() {
        guard let state = editor?.toolState, state.activeToolID == PlaybackTool.toolID else { return }
        state.select(restoreToolID ?? .pen)
        restoreToolID = nil
    }

    // MARK: RecordingInkSource and stroke helpers

    func timedStrokes(onPage pageID: UUID) -> [TimedStroke] {
        guard let page = page(pageID) else { return [] }
        return Self.timed(page.ink.strokes)
    }

    func page(_ id: UUID) -> (any PageContext)? {
        if let current = editor?.currentPage, current.pageID == id { return current }
        return editor?.visiblePages.first { $0.pageID == id }
    }

    static func timed(_ strokes: [IdentifiedStroke]) -> [TimedStroke] {
        strokes.map { TimedStroke(id: $0.id, creationDate: $0.stroke.path.creationDate) }
    }
}

/// One session per open notebook, created on first use.
@MainActor
final class AudioStudyHub {
    static let shared = AudioStudyHub()
    private var sessions: [UUID: AudioStudySession] = [:]
    /// Tests replace the factory with one that builds fake capture and player objects.
    var makeSession: @MainActor (UUID, AppServices) -> AudioStudySession = { id, services in
        AudioStudySession(notebookID: id, services: services)
    }

    func session(for editor: any EditorContext) -> AudioStudySession {
        let id = editor.notebook.id
        let session = sessions[id] ?? makeSession(id, editor.services)
        sessions[id] = session
        session.editor = editor
        return session
    }

    func reset() { sessions = [:] }
}
