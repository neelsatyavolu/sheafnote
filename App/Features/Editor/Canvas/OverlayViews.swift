import SwiftUI
import UIKit
import SheafnoteCore

/// Hosts the active tool's transient overlay (lasso path, laser trail, shape preview) in page coordinates.
/// It only takes touches when the tool asks for them; Pencil-only tools let fingers fall through to scrolling.
struct ToolOverlayContent: View {
    let page: PageSession
    let session: NotebookSession

    var body: some View {
        ZStack {
            if let tool = session.activeTool, let overlay = tool.makeOverlay(for: page, in: session) {
                overlay
            }
        }
        .frame(width: page.pageSize.width, height: page.pageSize.height, alignment: .topLeading)
    }
}

final class ToolOverlayView: HostedSwiftUIView<ToolOverlayContent> {
    private let session: NotebookSession

    init(page: PageSession, session: NotebookSession) {
        self.session = session
        super.init(rootView: ToolOverlayContent(page: page, session: session))
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let policy = session.activeTool?.inputPolicy, policy != .canvasHandlesInput else { return nil }
        if policy == .overlayCapturesPencil, event?.allTouches?.first?.type != .pencil { return nil }
        return super.hitTest(point, with: event)
    }
}

/// Hosts the selection handles and floating menu. Touches are taken only near the current selection.
final class SelectionOverlayView: HostedSwiftUIView<SelectionOverlayContent> {
    private let page: PageSession
    private let session: NotebookSession

    init(page: PageSession, session: NotebookSession) {
        self.page = page
        self.session = session
        super.init(rootView: SelectionOverlayContent(page: page, session: session))
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard session.selection.pageID == page.pageID, let bounds = session.selection.bounds else { return nil }
        let region = bounds.applying(session.selection.livePreviewTransform).insetBy(dx: -48, dy: -88)
        guard region.contains(point) else { return nil }
        return super.hitTest(point, with: event)
    }
}
