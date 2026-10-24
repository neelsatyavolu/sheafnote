import CoreGraphics
import Foundation
import SheafnoteCore

/// Highlighter "draw straight line": with the option on, every highlighter stroke is replaced, once it is finished,
/// by a straight line from where it started to where it ended (exactly horizontal or vertical when close to it).
@MainActor
final class StraightHighlighterObserver: InkTouchObserver {
    let activeToolIDs: Set<ToolID> = [.highlighter]

    private let settings: InkToolsSettings
    private var start: CGPoint?
    private var baseline = 0

    init(settings: InkToolsSettings) { self.settings = settings }

    func strokeBegan(_ s: InkSample, page: any PageContext, editor: EditorContext) {
        start = settings.straightHighlighter ? s.location : nil
        baseline = page.ink.strokes.count
    }

    func strokeMoved(_ samples: [InkSample], page: any PageContext, editor: EditorContext) {}

    func strokeEnded(_ s: InkSample, page: any PageContext, editor: EditorContext) {
        defer { start = nil }
        guard let start, let line = StraightLineFit.line(from: [start, s.location]) else { return }
        let baseline = baseline
        Task {
            await InkSnapper.replaceLastStroke(on: page, baseline: baseline, name: LocalizedStringResource("Straighten Line", table: "InkTools")) {
                SnappedStroke.line(replacing: $0, from: line.0, to: line.1)
            }
        }
    }

    func strokeCancelled(page: any PageContext, editor: EditorContext) { start = nil }
}
