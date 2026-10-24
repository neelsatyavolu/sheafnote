import PencilKit
import SheafnoteCore

/// Replaces the stroke the user has just finished. PencilKit adds a stroke to the page a moment after the pen lifts,
/// so the replacement waits for it, and gives up (leaving the original ink alone) if anything else changed meanwhile.
@MainActor
enum InkSnapper {
    static let pollInterval: Duration = .milliseconds(20)
    static let maxPolls = 40

    /// `baseline` is the stroke count when the stroke began; the new stroke must be exactly one more.
    /// Returns true when a stroke was replaced.
    @discardableResult
    static func replaceLastStroke(on page: any PageContext, baseline: Int, name: LocalizedStringResource,
                                  _ make: (PKStroke) -> PKStroke?) async -> Bool {
        for _ in 0..<maxPolls {
            if page.ink.strokes.count > baseline { break }
            do { try await Task.sleep(for: pollInterval) } catch { return false }
        }
        guard page.ink.strokes.count == baseline + 1, let last = page.ink.strokes.last,
              let replacement = make(last.stroke) else { return false }
        page.ink.edit(name) { strokes in
            guard strokes.count == baseline + 1 else { return }
            strokes[strokes.count - 1] = replacement
        }
        return true
    }
}
