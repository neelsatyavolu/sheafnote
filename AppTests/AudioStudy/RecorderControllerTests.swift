import Foundation
import Testing
import SheafnoteCore
@testable import Sheafnote

@MainActor
struct RecorderControllerTests {
    let services: AppServices
    let notebook: Notebook
    let capture = FakeAudioCapture()
    let ink = FakeRecordingInk()
    let directory = audioTemporaryDirectory()
    let center = NotificationCenter()
    let recorder: RecorderController
    let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

    init() throws {
        services = try AppServices.inMemory()
        notebook = try services.library.createNotebook(
            title: "N", kind: .paged, cover: .default, template: .blank, paperSize: .a4,
            orientation: .portrait, paperColor: .white, in: nil)
        let store = RecordingStore(context: services.context)
        let start = t0
        recorder = RecorderController(notebookID: notebook.id, capture: capture, store: store, pendingDirectory: directory,
                                      now: { start }, center: center)
        recorder.ink = ink
    }

    private var store: RecordingStore { RecordingStore(context: services.context) }

    @Test func deniedPermissionShowsDeniedStateAndRecordsNothing() async throws {
        capture.permission = .denied
        await recorder.start()
        #expect(recorder.state == .denied)
        #expect(capture.startedURL == nil)
        recorder.dismissProblem()
        #expect(recorder.state == .idle)
    }

    @Test func startFailureIsReportedNotSwallowed() async {
        capture.startError = AudioCaptureError.couldNotStart("busy")
        await recorder.start()
        guard case .failed(let message) = recorder.state else { Issue.record("expected failed"); return }
        #expect(message.contains("busy"))
    }

    @Test func recordAndStopStoresRecordingWithTimelineAndCleansUp() async throws {
        await recorder.start()
        #expect(recorder.isRecording)
        let page = UUID()
        ink.strokes[page] = [TimedStroke(id: StrokeID(rawValue: "a"), creationDate: t0.addingTimeInterval(3)),
                             TimedStroke(id: StrokeID(rawValue: "old"), creationDate: t0.addingTimeInterval(-500))]
        center.post(name: EditorNotifications.inkDidChange, object: page)
        await Task.yield()
        let saved = try #require(await recorder.stop())
        #expect(recorder.state == .idle)
        #expect(saved.duration == 12.5)
        #expect(saved.title == "Recording 1")
        let timeline = store.timeline(for: saved)
        #expect(timeline.marks.map(\.strokeID) == [StrokeID(rawValue: "a")])
        #expect(timeline.marks.first?.offset == 3)
        #expect(timeline.marks.first?.pageID == page)
        #expect(try store.audioData(for: saved) == capture.bytes)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(leftovers.isEmpty)
    }

    @Test func strokesAreMarkedOnlyOnce() async throws {
        await recorder.start()
        let page = UUID()
        ink.strokes[page] = [TimedStroke(id: StrokeID(rawValue: "a"), creationDate: t0.addingTimeInterval(1))]
        recorder.inkChanged(pageID: page)
        ink.strokes[page]?.append(TimedStroke(id: StrokeID(rawValue: "b"), creationDate: t0.addingTimeInterval(2)))
        recorder.inkChanged(pageID: page)
        let saved = try #require(await recorder.stop())
        #expect(store.timeline(for: saved).marks.count == 2)
    }

    @Test func emptyAudioFailsAndNothingIsStored() async throws {
        capture.bytes = Data()
        await recorder.start()
        let saved = await recorder.stop()
        #expect(saved == nil)
        guard case .failed = recorder.state else { Issue.record("expected failed"); return }
        #expect(try store.recordings(in: notebook.id).isEmpty)
    }

    @Test func interruptionSavesWhatWasRecordedAndExplains() async throws {
        await recorder.start()
        capture.onInterruption?(.interrupted)
        for _ in 0..<20 where recorder.isRecording || recorder.state == .saving { try await Task.sleep(for: .milliseconds(20)) }
        #expect(recorder.state == .idle)
        #expect(recorder.notice != nil)
        #expect(try store.recordings(in: notebook.id).count == 1)
    }

    @Test func stopWithoutStartDoesNothing() async {
        #expect(await recorder.stop() == nil)
        #expect(capture.stopCount == 0)
    }

    @Test func secondStartWhileRecordingIsIgnored() async {
        await recorder.start()
        let url = capture.startedURL
        await recorder.start()
        #expect(capture.startedURL == url)
    }

    @Test func leftoverFilesFromACrashAreRecovered() throws {
        let file = directory.appendingPathComponent("\(notebook.id.uuidString)_\(UUID().uuidString).m4a")
        try Data([9, 9, 9]).write(to: file)
        let other = directory.appendingPathComponent("\(UUID().uuidString)_x.m4a")
        try Data([8]).write(to: other)
        let recovered = recorder.recoverPending()
        #expect(recovered.count == 1)
        #expect(recovered[0].duration == 7)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(FileManager.default.fileExists(atPath: other.path), "another notebook's file is left alone")
    }
}
