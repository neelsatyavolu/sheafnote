import SwiftUI
import SheafnoteCore

/// The magnified writing strip: shows the focus box enlarged and turns what is written into page ink.
struct ZoomStripView: View {
    let controller: ZoomWindowController
    @Environment(\.displayScale) private var displayScale

    private var acceptsFingers: Bool { controller.editor?.toolState.inputMode != .pencilOnly }

    var body: some View {
        ZStack {
            Color.white
            Canvas { context, size in draw(in: &context, size: size) }
            StripInputView(
                acceptsFingers: acceptsFingers,
                onBegan: { controller.strokeBegan($0) },
                onMoved: { controller.strokeMoved($0) },
                onEnded: { controller.strokeEnded($0) },
                onCancelled: { controller.strokeCancelled() }
            )
        }
        .frame(maxWidth: .infinity, minHeight: 110, maxHeight: 110)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.accentColor.opacity(0.6), lineWidth: 1.5))
        .background(GeometryReader { proxy in
            Color.clear
                .onAppear { controller.stripLayoutChanged(size: proxy.size, displayScale: displayScale) }
                .onChange(of: proxy.size) { _, size in controller.stripLayoutChanged(size: size, displayScale: displayScale) }
        })
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Zoom window writing area", tableName: "Present"))
        .accessibilityHint(Text("Write here with Apple Pencil. Your writing appears on the page.", tableName: "Present"))
        .accessibilityIdentifier("present.zoom.strip")
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        if let image = controller.stripImage {
            context.draw(Image(decorative: image, scale: 1), in: CGRect(origin: .zero, size: size))
        }
        let spec = controller.inkSpec
        let color = Color(uiColor: spec?.color ?? .black)
        let lineWidth = (spec?.width ?? 3) / max(controller.model.pageScale(forStrip: size), 0.001)
        for samples in controller.pendingStrokes + [controller.liveSamples] where !samples.isEmpty {
            var path = Path()
            path.move(to: samples[0].location)
            samples.dropFirst().forEach { path.addLine(to: $0.location) }
            if samples.count == 1 { path.addLine(to: CGPoint(x: samples[0].location.x + 0.1, y: samples[0].location.y)) }
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
        }
    }
}

/// The floating panel content: the strip plus close and next-line buttons.
struct ZoomPanelView: View {
    let controller: ZoomWindowController
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Label { Text("Zoom Window", tableName: "Present") } icon: { Image(systemName: "text.magnifyingglass") }
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if let message = controller.errorMessage {
                    Text(message).font(.footnote).foregroundStyle(.red).lineLimit(1)
                        .accessibilityIdentifier("present.zoom.error")
                }
                Button { controller.newLine() } label: {
                    Label { Text("New Line", tableName: "Present") } icon: { Image(systemName: "return") }
                }
                .accessibilityIdentifier("present.zoom.newLine")
                Button { onClose() } label: { Image(systemName: "xmark.circle.fill").imageScale(.large) }
                    .accessibilityLabel(Text("Close zoom window", tableName: "Present"))
                    .accessibilityIdentifier("present.zoom.close")
            }
            .labelStyle(.titleAndIcon)
            ZoomStripView(controller: controller)
        }
        .padding(12)
        .frame(maxWidth: 760)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22))
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }
}
