import AVFoundation
import Foundation
import Observation
import SheafnoteCore

/// The speaker side of playback. The real one wraps `AVAudioPlayer`; tests use a fake.
@MainActor
protocol AudioPlaying: AnyObject {
    var duration: Double { get }
    var currentTime: Double { get set }
    var isPlaying: Bool { get }
    var rate: Float { get set }
    var onFinished: (@MainActor () -> Void)? { get set }
    func load(_ data: Data) throws
    func play()
    func pause()
    func stop()
}

@MainActor
final class AVAudioPlayerBox: NSObject, AudioPlaying, AVAudioPlayerDelegate {
    var onFinished: (@MainActor () -> Void)?
    private var player: AVAudioPlayer?

    var duration: Double { player?.duration ?? 0 }
    var isPlaying: Bool { player?.isPlaying ?? false }
    var currentTime: Double {
        get { player?.currentTime ?? 0 }
        set { player?.currentTime = newValue }
    }
    var rate: Float {
        get { player?.rate ?? 1 }
        set { player?.rate = newValue }
    }

    func load(_ data: Data) throws {
        try AVAudioSession.sharedInstance().setCategory(.playback)
        try AVAudioSession.sharedInstance().setActive(true)
        let p = try AVAudioPlayer(data: data)
        p.enableRate = true
        p.delegate = self
        p.prepareToPlay()
        player = p
    }

    func play() { player?.play() }
    func pause() { player?.pause() }
    func stop() {
        player?.stop()
        player = nil
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in self?.onFinished?() }
    }
}

enum PlaybackError: LocalizedError {
    case unreadable

    var errorDescription: String? {
        String(localized: "This recording could not be played. The audio may be damaged or still downloading from iCloud.",
               table: "AudioStudy")
    }
}

/// Plays one recording and answers "where is the playhead" for the stroke overlay.
@MainActor @Observable
final class PlaybackController {
    private(set) var recording: AudioRecording?
    private(set) var timeline = AudioTimeline(startedAt: .distantPast, duration: 0)
    private(set) var isPlaying = false
    private(set) var currentTime: Double = 0
    private(set) var duration: Double = 0
    private(set) var errorMessage: String?
    var rate: Float = 1 { didSet { player.rate = rate } }

    var isLoaded: Bool { recording != nil }

    private let player: any AudioPlaying
    private var ticker: Task<Void, Never>?

    init(player: any AudioPlaying) {
        self.player = player
        player.onFinished = { [weak self] in self?.finished() }
    }

    func load(_ recording: AudioRecording, audio: Data, timeline: AudioTimeline) {
        stopTicker()
        do {
            try player.load(audio)
        } catch {
            errorMessage = PlaybackError.unreadable.localizedDescription
            unload()
            return
        }
        self.recording = recording
        self.timeline = timeline
        duration = player.duration > 0 ? player.duration : timeline.duration
        currentTime = 0
        errorMessage = nil
        player.rate = rate
    }

    func unload() {
        stopTicker()
        player.stop()
        recording = nil
        isPlaying = false
        currentTime = 0
        duration = 0
    }

    func play() {
        guard isLoaded else { return }
        if currentTime >= duration - 0.05 { seek(to: 0) }
        player.play()
        isPlaying = true
        startTicker()
    }

    func pause() {
        player.pause()
        isPlaying = false
        stopTicker()
        currentTime = player.currentTime
    }

    func togglePlay() { isPlaying ? pause() : play() }

    func seek(to seconds: Double) {
        let t = min(max(0, seconds), max(duration, 0))
        player.currentTime = t
        currentTime = t
    }

    /// Jumps to the moment a stroke was written. `leadIn` starts that many seconds earlier.
    @discardableResult
    func seek(toStroke stroke: TimedStroke, leadIn: Double = 0, play shouldPlay: Bool = true) -> Bool {
        guard isLoaded, let offset = timeline.offset(for: stroke) else { return false }
        seek(to: max(0, offset - leadIn))
        if shouldPlay, !isPlaying { play() }
        return true
    }

    func dimmedStrokeIDs(among strokes: [TimedStroke]) -> Set<StrokeID> {
        guard isLoaded else { return [] }
        return timeline.strokesAfter(playhead: currentTime, among: strokes)
    }

    func skip(by seconds: Double) { seek(to: currentTime + seconds) }

    private func finished() {
        isPlaying = false
        stopTicker()
        currentTime = duration
    }

    private func startTicker() {
        stopTicker()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard let self, self.isPlaying else { return }
                self.currentTime = self.player.currentTime
            }
        }
    }

    private func stopTicker() {
        ticker?.cancel()
        ticker = nil
    }
}
