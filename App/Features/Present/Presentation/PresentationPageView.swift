import SwiftUI
import SheafnoteCore

/// The page as the audience sees it: the page alone on black, with the laser and (optionally) the zoom window.
/// Used by the external display and by the presenter on the device.
struct PresentationPageView: View {
    let controller: PresentationController
    var showsLaser: Bool
    var showsZoomWindow: Bool
    /// When set, touches on the page move the laser (device presenter). Page coordinates.
    var onLaserTouch: ((CGPoint?, CGFloat) -> Void)?

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black
                content(in: proxy.size)
            }
            .onAppear { updateTarget(proxy.size) }
            .onChange(of: proxy.size) { _, size in updateTarget(size) }
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private func content(in size: CGSize) -> some View {
        let mirror = controller.mirror
        if let image = mirror.image {
            let fit = AspectFit(content: mirror.pageSize, in: size)
            ZStack(alignment: .topLeading) {
                Image(decorative: image, scale: 1).resizable()
                    .frame(width: fit.rect.width, height: fit.rect.height)
                    .position(x: fit.rect.midX, y: fit.rect.midY)
                if showsLaser, let laser = controller.laser { laserLayer(laser, fit: fit, size: size) }
                if showsZoomWindow, let zoom = controller.zoom, zoom.isActive, zoom.pageID == mirror.pageID {
                    zoomLayer(zoom, fit: fit, size: size)
                }
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .contentShape(Rectangle())
            .gesture(laserGesture(fit: fit))
        } else {
            Text(mirror.errorMessage ?? String(localized: "Waiting for the page…", table: "Present"))
                .foregroundStyle(.white.opacity(0.7))
                .accessibilityIdentifier("present.waiting")
        }
    }

    private func laserLayer(_ laser: LaserController, fit: AspectFit, size: CGSize) -> some View {
        TimelineView(.animation(paused: !laser.isAnimating)) { _ in
            Canvas { context, _ in
                guard laser.pageID == controller.mirror.pageID else { return }
                context.translateBy(x: fit.rect.minX, y: fit.rect.minY)
                context.scaleBy(x: fit.scale, y: fit.scale)
                LaserPainter.draw(laser.model, color: laser.color, diameter: CGFloat(laser.diameter) * laser.pageUnitsPerPoint,
                                  now: LaserController.now(), in: &context)
            }
        }
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(false)
    }

    private func zoomLayer(_ zoom: ZoomWindowController, fit: AspectFit, size: CGSize) -> some View {
        let focus = zoom.model.focusRect
        let box = CGRect(x: fit.rect.minX + focus.minX * fit.scale, y: fit.rect.minY + focus.minY * fit.scale,
                         width: focus.width * fit.scale, height: focus.height * fit.scale)
        let insetWidth = min(size.width * 0.8, 1400)
        let insetHeight = insetWidth * focus.height / max(focus.width, 1)
        return ZStack(alignment: .topLeading) {
            Rectangle().strokeBorder(Color.accentColor, lineWidth: 2).frame(width: box.width, height: box.height)
                .offset(x: box.minX, y: box.minY)
            if let strip = zoom.stripImage {
                Image(decorative: strip, scale: 1).resizable()
                    .frame(width: insetWidth, height: insetHeight)
                    .overlay(Rectangle().strokeBorder(Color.accentColor, lineWidth: 3))
                    .offset(x: (size.width - insetWidth) / 2, y: size.height - insetHeight - 24)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .allowsHitTesting(false)
    }

    private func laserGesture(fit: AspectFit) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in onLaserTouch?(fit.pagePoint(forView: value.location), fit.scale) }
            .onEnded { _ in onLaserTouch?(nil, fit.scale) }
    }

    private func updateTarget(_ size: CGSize) {
        controller.mirror.targetPixelWidth = min(max(size.width * displayScale, 800), 3200)
    }
}
