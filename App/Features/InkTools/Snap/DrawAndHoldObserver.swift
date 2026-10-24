import Foundation
import UIKit
import SheafnoteCore

/// Draw and hold with the pen: when the pen stays still for a moment at the end of a stroke, the stroke is replaced
/// by the clean shape it was meant to be. PencilKit keeps drawing the stroke itself; this only watches the touches
/// and swaps the finished stroke afterwards, as one undo step of its own, so undo brings the hand-drawn stroke back.
@MainActor
final class DrawAndHoldObserver: InkTouchObserver {
    let activeToolIDs: Set<ToolID> = [.pen]
    static let pollInterval: Duration = .milliseconds(100)

    private let settings: InkToolsSettings
    private var detector = HoldDetector()
    private var samples: [CGPoint] = []
    private var armed: ShapeFigure?
    private var baseline = 0
    private var watcher: Task<Void, Never>?

    init(settings: InkToolsSettings) { self.settings = settings }

    func strokeBegan(_ s: InkSample, page: any PageContext, editor: EditorContext) {
        reset()
        guard settings.drawAndHold else { return }
        baseline = page.ink.strokes.count
        samples = [s.location]
        detector.begin(at: s.location, time: s.timestamp)
        watch()
    }

    func strokeMoved(_ moved: [InkSample], page: any PageContext, editor: EditorContext) {
        guard detector.isTracking else { return }
        for s in moved {
            samples.append(s.location)
            detector.move(to: s.location, time: s.timestamp)
        }
    }

    func strokeEnded(_ s: InkSample, page: any PageContext, editor: EditorContext) {
        defer { reset() }
        guard detector.isTracking else { return }
        samples.append(s.location)
        guard detector.isHeld(at: Self.now), let figure = armed ?? ShapeRecognizer.recognize(samples) else { return }
        let baseline = baseline
        Task {
            await InkSnapper.replaceLastStroke(on: page, baseline: baseline, name: LocalizedStringResource("Snap to Shape", table: "InkTools")) {
                SnappedStroke.make(replacing: $0, with: figure)
            }
        }
    }

    func strokeCancelled(page: any PageContext, editor: EditorContext) { reset() }

    // MARK: Hold watching

    static var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    private func reset() {
        watcher?.cancel()
        watcher = nil
        detector.reset()
        samples = []
        armed = nil
    }

    /// While the pen is down: once it has been still long enough, work out the shape and tick, so the user knows
    /// lifting now will snap. Moving again withdraws it.
    private func watch() {
        watcher = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: Self.pollInterval) } catch { return }
                self?.checkHold()
            }
        }
    }

    private func checkHold() {
        if detector.isHeld(at: Self.now) {
            guard armed == nil, let figure = ShapeRecognizer.recognize(samples) else { return }
            armed = figure
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } else {
            armed = nil
        }
    }
}
