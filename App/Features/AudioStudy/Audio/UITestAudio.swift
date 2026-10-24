import Foundation

/// Scripted microphone and speaker for UI tests (`-UITestMode 1`): no hardware, no permission prompt.
/// `-UITestMicDenied 1` makes the permission request come back denied.
enum UITestAudio {
    static var isActive: Bool { UserDefaults.standard.bool(forKey: "UITestMode") }
    static var micDenied: Bool { UserDefaults.standard.bool(forKey: "UITestMicDenied") }

    @MainActor static func capture() -> any AudioCapturing { isActive ? ScriptedCapture() : AVAudioRecorderCapture() }
    @MainActor static func player() -> any AudioPlaying { isActive ? ScriptedPlayer() : AVAudioPlayerBox() }
}

@MainActor
final class ScriptedCapture: AudioCapturing {
    var onInterruption: (@MainActor (CaptureInterruption) -> Void)?
    private var startedAt: Date?

    var currentTime: Double { startedAt.map { Date().timeIntervalSince($0) } ?? 0 }

    func requestPermission() async -> MicrophonePermission { UITestAudio.micDenied ? .denied : .granted }

    func start(to url: URL, quality: RecordingQuality) throws {
        try Data(repeating: 7, count: 2_048).write(to: url)
        startedAt = Date()
    }

    func stop() -> Double {
        defer { startedAt = nil }
        return max(1, currentTime)
    }

    func duration(ofFileAt url: URL) -> Double { 1 }
}

@MainActor
final class ScriptedPlayer: AudioPlaying {
    var duration: Double = 60
    var rate: Float = 1
    var onFinished: (@MainActor () -> Void)?
    private var base: Double = 0
    private var playingSince: Date?

    var isPlaying: Bool { playingSince != nil }

    var currentTime: Double {
        get {
            guard let playingSince else { return base }
            return min(duration, base + Date().timeIntervalSince(playingSince) * Double(rate))
        }
        set {
            base = newValue
            if playingSince != nil { playingSince = Date() }
        }
    }

    func load(_ data: Data) throws { base = 0 }
    func play() { playingSince = Date() }
    func pause() {
        base = currentTime
        playingSince = nil
    }
    func stop() {
        playingSince = nil
        base = 0
    }
}
