import SwiftUI

/// The laser's surface above one page: any touch moves the pointer, nothing is written to the page.
struct LaserOverlay: View {
    let page: any PageContext
    let controller: LaserController

    var body: some View {
        let pageID = page.pageID
        TimelineView(.animation(paused: !controller.isAnimating)) { _ in
            Canvas { context, _ in
                guard controller.pageID == pageID else { return }
                let diameter = CGFloat(controller.diameter) / max(page.zoomScale, 0.05)
                LaserPainter.draw(controller.model, color: controller.color, diameter: diameter,
                                  now: LaserController.now(), in: &context)
            }
        }
        .frame(width: page.pageSize.width, height: page.pageSize.height)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { controller.touchMoved(on: pageID, at: $0.location, zoomScale: page.zoomScale) }
                .onEnded { _ in controller.touchEnded() }
        )
        .accessibilityHidden(true)
    }
}
