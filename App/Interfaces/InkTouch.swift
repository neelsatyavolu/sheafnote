import CoreGraphics
import Foundation

struct InkSample: Sendable {
    /// Page coordinates.
    var location: CGPoint
    var timestamp: TimeInterval
    var force: CGFloat
    var altitude: CGFloat
    var azimuth: CGFloat
    var isPencil: Bool
}

/// PencilKit does not expose a stroke in progress. The editor's canvas host forwards raw touches here.
@MainActor
protocol InkTouchObserver: AnyObject {
    /// Only called while one of these is the active tool.
    var activeToolIDs: Set<ToolID> { get }
    func strokeBegan(_ s: InkSample, page: any PageContext, editor: EditorContext)
    /// Coalesced, predicted samples removed.
    func strokeMoved(_ samples: [InkSample], page: any PageContext, editor: EditorContext)
    func strokeEnded(_ s: InkSample, page: any PageContext, editor: EditorContext)
    func strokeCancelled(page: any PageContext, editor: EditorContext)
}

@MainActor
final class InkTouchObserverRegistry {
    private(set) var observers: [any InkTouchObserver] = []

    func register(_ o: any InkTouchObserver) { observers.append(o) }
    func observers(for tool: ToolID) -> [any InkTouchObserver] { observers.filter { $0.activeToolIDs.contains(tool) } }
}
