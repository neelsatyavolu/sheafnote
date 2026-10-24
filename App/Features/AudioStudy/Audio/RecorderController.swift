import Foundation
import Observation
import OSLog
import SheafnoteCore

/// Gives the recorder the strokes of a page so it can note when each one was written.
@MainActor
protocol RecordingInkSource: AnyObject {
    func timedStrokes(onPage pageID: UUID) -> [TimedStroke]
}

/// Records audio for one notebook while the person writes, and stores the result with a stroke timeline.
///
/// States: idle -> requestingPermission -> recording -> saving -> idle. Permission denied and failures are
/// shown to the person; nothing is dropped silently. If saving fails the audio file stays on disk in the
/// pending folder and is imported on the next launch.
@MainActor @Observable
final class RecorderController {
    enum State: Equatable {
        case idle, requestingPermission, recording, saving, denied
        case failed(String)
    }

    private static let log = Logger(subsystem: "co.xanom.sheafnote", category: "audio")

    private(set) var state: State = .idle
    private(set) var elapsed: Double = 0
    private(set) var notice: String?

    var isRecording: Bool { state == .recording }
    var isBusy: Bool { state == .requestingPermission || state == .saving }

    private let notebookID: UUID
    private let capture: any AudioCapturing
    private let store: RecordingStore
    private let quality: @MainActor () -> RecordingQuality
    private let now: @MainActor () -> Date
    private let pendingDirectory: URL
    private let center: NotificationCenter
    weak var ink: (any RecordingInkSource)?
    var onSaved: (@MainActor (AudioRecording) -> Void)?

    private var timeline = AudioTimeline(startedAt: .now, duration: 0)
    private var seen: Set<StrokeID> = []
    private var fileURL: URL?
    private var ticker: Task<Void, Never>?
    private var inkObserver: NSObjectProtocol?

    init(notebookID: UUID, capture: any AudioCapturing, store: RecordingStore, pendingDirectory: URL,
         quality: @escaping @MainActor () -> RecordingQuality = { .standard },
         now: @escaping @MainActor () -> Date = { Date() }, center: NotificationCenter = .default) {
        self.notebookID = notebookID
        self.capture = capture
        self.store = store
        self.pendingDirectory = pendingDirectory
        self.quality = quality
        self.now = now
        self.center = center
        capture.onInterruption = { [weak self] event in self?.handle(event) }
    }

    // MARK: Start and stop

    func start() async {
        guard state == .idle || state == .denied || isFailed else { return }
        notice = nil
        state = .requestingPermission
        guard await capture.requestPermission() == .granted else {
            state = .denied
            return
        }
        do {
            try FileManager.default.createDirectory(at: pendingDirectory, withIntermediateDirectories: true)
            let url = pendingDirectory.appendingPathComponent("\(notebookID.uuidString)_\(UUID().uuidString).m4a")
            try capture.start(to: url, quality: quality())
            fileURL = url
            timeline = AudioTimeline(startedAt: now(), duration: 0)
            seen = []
            elapsed = 0
            state = .recording
            observeInk()
            startTicker()
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    @discardableResult
    func stop() async -> AudioRecording? {
        guard state == .recording else { return nil }
        stopObservingAndTicking()
        state = .saving
        let length = capture.stop()
        elapsed = length
        guard let url = fileURL else {
            state = .failed(AudioCaptureError.nothingRecorded.localizedDescription)
            return nil
        }
        fileURL = nil
        return save(fileAt: url, timeline: timeline.finished(duration: length))
    }

    private func save(fileAt url: URL, timeline: AudioTimeline) -> AudioRecording? {
        do {
            let data = try Data(contentsOf: url)
            guard !data.isEmpty else {
                try? FileManager.default.removeItem(at: url)
                state = .failed(AudioCaptureError.nothingRecorded.localizedDescription)
                return nil
            }
            let title = try store.nextTitle(in: notebookID, prefix: String(localized: "Recording", table: "AudioStudy"))
            let saved = try store.save(notebookID: notebookID, audio: data, title: title, timeline: timeline)
            try? FileManager.default.removeItem(at: url)
            state = .idle
            onSaved?(saved)
            return saved
        } catch {
            Self.log.error("Saving recording failed: \(error.localizedDescription, privacy: .public)")
            state = .failed(String(localized: "The recording could not be saved (\(error.localizedDescription)). The audio is kept on this device and Sheafnote will try again next time it opens.",
                                   table: "AudioStudy"))
            return nil
        }
    }

    private var isFailed: Bool {
        if case .failed = state { return true }
        return false
    }

    private func handle(_ event: CaptureInterruption) {
        guard state == .recording else { return }
        Task {
            let saved = await stop()
            switch event {
            case .interrupted:
                notice = saved == nil ? nil : String(localized: "Recording stopped because another app used the microphone. What was recorded is saved.",
                                                    table: "AudioStudy")
            case .failed(let why):
                if saved != nil {
                    notice = String(localized: "Recording stopped early (\(why)). What was recorded is saved.", table: "AudioStudy")
                }
            }
        }
    }

    // MARK: Crash recovery

    /// Imports audio left in the pending folder by an earlier run that could not finish saving.
    @discardableResult
    func recoverPending() -> [AudioRecording] {
        let files = (try? FileManager.default.contentsOfDirectory(at: pendingDirectory, includingPropertiesForKeys: nil)) ?? []
        var recovered: [AudioRecording] = []
        for url in files where url.lastPathComponent.hasPrefix(notebookID.uuidString) && url != fileURL {
            let length = capture.duration(ofFileAt: url)
            guard length > 0 else { continue }
            let created = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? now()
            let tl = AudioTimeline(startedAt: created.addingTimeInterval(-length), duration: length)
            guard let data = try? Data(contentsOf: url), !data.isEmpty else { continue }
            do {
                let title = String(localized: "Recovered recording", table: "AudioStudy")
                recovered.append(try store.save(notebookID: notebookID, audio: data, title: title, timeline: tl))
                try? FileManager.default.removeItem(at: url)
            } catch {
                Self.log.error("Recovery failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        return recovered
    }

    // MARK: Stroke timeline

    private func observeInk() {
        inkObserver = center.addObserver(forName: EditorNotifications.inkDidChange, object: nil, queue: .main) { [weak self] note in
            guard let pageID = note.object as? UUID else { return }
            MainActor.assumeIsolated { self?.inkChanged(pageID: pageID) }
        }
    }

    func inkChanged(pageID: UUID) {
        guard state == .recording, let strokes = ink?.timedStrokes(onPage: pageID) else { return }
        let start = timeline.startedAt
        for s in strokes where !seen.contains(s.id) {
            seen.insert(s.id)
            let offset = s.creationDate.timeIntervalSince(start)
            guard offset >= -AudioTimeline.edgeTolerance else { continue }
            timeline = timeline.adding(AudioStrokeMark(pageID: pageID, strokeID: s.id, offset: max(0, offset)))
        }
    }

    private func startTicker() {
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard let self, self.state == .recording else { return }
                self.elapsed = self.capture.currentTime
            }
        }
    }

    private func stopObservingAndTicking() {
        ticker?.cancel()
        ticker = nil
        if let inkObserver { center.removeObserver(inkObserver) }
        inkObserver = nil
    }

    func dismissProblem() {
        if state == .denied || isFailed { state = .idle }
    }
}
