import Foundation
import SheafnoteCore
@testable import Sheafnote

/// Stand-in for the microphone: writes a few bytes to the file it is given.
@MainActor
final class FakeAudioCapture: AudioCapturing {
    var onInterruption: (@MainActor (CaptureInterruption) -> Void)?
    var permission: MicrophonePermission = .granted
    var startError: Error?
    var bytes = Data([1, 2, 3, 4])
    var length: Double = 12.5
    var currentTime: Double = 0
    private(set) var startedURL: URL?
    private(set) var stopCount = 0
    var fileLength: Double = 7

    func requestPermission() async -> MicrophonePermission { permission }

    func start(to url: URL, quality: RecordingQuality) throws {
        if let startError { throw startError }
        startedURL = url
        try bytes.write(to: url)
    }

    func stop() -> Double {
        stopCount += 1
        return length
    }

    func duration(ofFileAt url: URL) -> Double { fileLength }
}

@MainActor
final class FakeAudioPlayer: AudioPlaying {
    var duration: Double = 60
    var currentTime: Double = 0
    private(set) var isPlaying = false
    var rate: Float = 1
    var onFinished: (@MainActor () -> Void)?
    var loadError: Error?
    private(set) var loadCount = 0

    func load(_ data: Data) throws {
        if let loadError { throw loadError }
        loadCount += 1
    }
    func play() { isPlaying = true }
    func pause() { isPlaying = false }
    func stop() { isPlaying = false }
}

@MainActor
final class FakeRecordingInk: RecordingInkSource {
    var strokes: [UUID: [TimedStroke]] = [:]
    func timedStrokes(onPage pageID: UUID) -> [TimedStroke] { strokes[pageID] ?? [] }
}

func audioTemporaryDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("sheafnote-audio-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
