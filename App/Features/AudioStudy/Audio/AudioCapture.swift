import AVFoundation
import Foundation
import OSLog

enum MicrophonePermission: Equatable, Sendable { case granted, denied }

enum RecordingQuality: String, CaseIterable, Sendable {
    case standard, high

    static let settingsKey = "audio.quality"

    var sampleRate: Double { self == .high ? 44_100 : 22_050 }
    var bitRate: Int { self == .high ? 96_000 : 48_000 }
}

enum AudioCaptureError: LocalizedError {
    case couldNotStart(String)
    case nothingRecorded

    var errorDescription: String? {
        switch self {
        case .couldNotStart(let why):
            String(localized: "Recording could not start (\(why)). Check that no other app is using the microphone and try again.",
                   table: "AudioStudy")
        case .nothingRecorded:
            String(localized: "Nothing was recorded.", table: "AudioStudy")
        }
    }
}

/// Reasons a recording ended without the user asking.
enum CaptureInterruption: Equatable, Sendable { case interrupted, failed(String) }

/// The microphone side of recording. The real one wraps `AVAudioRecorder`; tests use a fake.
@MainActor
protocol AudioCapturing: AnyObject {
    /// Called when the system takes the microphone away (phone call, Siri) or encoding fails.
    var onInterruption: (@MainActor (CaptureInterruption) -> Void)? { get set }
    func requestPermission() async -> MicrophonePermission
    func start(to url: URL, quality: RecordingQuality) throws
    /// Stops and returns the recorded length in seconds.
    func stop() -> Double
    var currentTime: Double { get }
    /// Length of an audio file on disk, used when recovering recordings after a crash.
    func duration(ofFileAt url: URL) -> Double
}

@MainActor
final class AVAudioRecorderCapture: NSObject, AudioCapturing, AVAudioRecorderDelegate {
    var onInterruption: (@MainActor (CaptureInterruption) -> Void)?
    private var recorder: AVAudioRecorder?
    private var observer: NSObjectProtocol?

    var currentTime: Double { recorder?.currentTime ?? 0 }

    func requestPermission() async -> MicrophonePermission {
        await withCheckedContinuation { cont in
            AVAudioApplication.requestRecordPermission { granted in
                cont.resume(returning: granted ? .granted : .denied)
            }
        }
    }

    func start(to url: URL, quality: RecordingQuality) throws {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true)
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: quality.sampleRate,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: quality.bitRate,
            ]
            let rec = try AVAudioRecorder(url: url, settings: settings)
            rec.delegate = self
            guard rec.prepareToRecord(), rec.record() else { throw AudioCaptureError.couldNotStart("the recorder refused to start") }
            recorder = rec
            observeInterruptions(session)
        } catch let error as AudioCaptureError {
            throw error
        } catch {
            throw AudioCaptureError.couldNotStart(error.localizedDescription)
        }
    }

    func stop() -> Double {
        let length = recorder?.currentTime ?? 0
        recorder?.stop()
        recorder = nil
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            // The recording itself is already stopped and saved; a session that stays active only delays other apps' audio.
            Logger(subsystem: "co.xanom.sheafnote", category: "audio")
                .error("Could not release the audio session: \(error.localizedDescription, privacy: .public)")
        }
        return length
    }

    func duration(ofFileAt url: URL) -> Double {
        (try? AVAudioPlayer(contentsOf: url))?.duration ?? 0
    }

    private func observeInterruptions(_ session: AVAudioSession) {
        observer = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: session, queue: .main) { [weak self] note in
                let began = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt)
                    .flatMap(AVAudioSession.InterruptionType.init(rawValue:)) == .began
                guard began else { return }
                MainActor.assumeIsolated { self?.onInterruption?(.interrupted) }
            }
    }

    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        let text = error?.localizedDescription ?? "unknown error"
        Task { @MainActor [weak self] in self?.onInterruption?(.failed(text)) }
    }
}
