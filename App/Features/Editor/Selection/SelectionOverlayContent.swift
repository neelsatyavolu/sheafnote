import SwiftUI
import UIKit
import SheafnoteCore

/// Selection frame with corner handles (scale), a rotate handle, drag-to-move and the floating action menu built from
/// `SelectionActionRegistry`. The lasso gesture that creates a selection belongs to another unit.
struct SelectionOverlayContent: View {
    let page: PageSession
    let session: NotebookSession

    @State private var lift: (image: UIImage, rect: CGRect)?
    @State private var dragActive = false

    private var selection: SelectionModel { session.selection }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if selection.pageID == page.pageID, let bounds = selection.bounds, !selection.isEmpty {
                content(bounds: bounds)
            }
        }
        .frame(width: page.pageSize.width, height: page.pageSize.height, alignment: .topLeading)
        .onChange(of: dragActive) { _, active in if !active { finishLiftIfNeeded() } }
    }

    // MARK: Drawing

    @ViewBuilder
    private func content(bounds: CGRect) -> some View {
        let t = selection.livePreviewTransform
        let corners = SelectionGeometry.corners(of: bounds, under: t)
        let zoom = max(session.zoomScale, 0.05)
        let handle = 20 / zoom
        if let lift {
            Canvas { ctx, _ in
                ctx.concatenate(t)
                ctx.draw(Image(uiImage: lift.image), in: lift.rect)
            }
            .allowsHitTesting(false)
        }
        quad(corners)
            .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1.5 / zoom, dash: [6 / zoom, 4 / zoom]))
            .allowsHitTesting(false)
        quad(corners).fill(Color.accentColor.opacity(0.001))
            .contentShape(quad(corners))
            .gesture(moveGesture(bounds: bounds))
            .accessibilityLabel(Text("Selection", tableName: "Editor"))
            .accessibilityHint(Text("Drag to move the selected items", tableName: "Editor"))
        ForEach(0..<4, id: \.self) { i in
            Circle().fill(Color.white).overlay(Circle().stroke(Color.accentColor, lineWidth: 2 / zoom))
                .frame(width: handle, height: handle)
                .position(corners[i])
                .gesture(scaleGesture(bounds: bounds, corner: i))
                .accessibilityLabel(Text("Resize handle", tableName: "Editor"))
        }
        rotateHandle(bounds: bounds, corners: corners, size: handle)
        floatingMenu(corners: corners, zoom: zoom)
    }

    private func quad(_ corners: [CGPoint]) -> Path {
        Path { p in
            p.move(to: corners[0])
            corners.dropFirst().forEach { p.addLine(to: $0) }
            p.closeSubpath()
        }
    }

    private func rotateHandle(bounds: CGRect, corners: [CGPoint], size: CGFloat) -> some View {
        let top = CGPoint(x: (corners[0].x + corners[1].x) / 2, y: (corners[0].y + corners[1].y) / 2)
        let center = CGPoint(x: (corners[0].x + corners[2].x) / 2, y: (corners[0].y + corners[2].y) / 2)
        let dx = top.x - center.x, dy = top.y - center.y
        let length = max(hypot(dx, dy), 0.001)
        let spot = CGPoint(x: top.x + dx / length * size * 1.8, y: top.y + dy / length * size * 1.8)
        return Image(systemName: "arrow.triangle.2.circlepath")
            .font(.system(size: size * 0.7))
            .frame(width: size * 1.3, height: size * 1.3)
            .background(Circle().fill(Color.white))
            .overlay(Circle().stroke(Color.accentColor, lineWidth: 2 / max(session.zoomScale, 0.05)))
            .position(spot)
            .gesture(rotateGesture(bounds: bounds))
            .accessibilityLabel(Text("Rotate handle", tableName: "Editor"))
    }

    // MARK: Menu

    @ViewBuilder
    private func floatingMenu(corners: [CGPoint], zoom: CGFloat) -> some View {
        let actions = session.host.selectionActions.actions.filter { $0.isEnabled(for: selection, editor: session) }
        if !actions.isEmpty, selection.livePreviewTransform == .identity {
            let top = corners.map(\.y).min() ?? 0
            let centerX = ((corners.map(\.x).min() ?? 0) + (corners.map(\.x).max() ?? 0)) / 2
            HStack(spacing: 2) {
                ForEach(actions, id: \.id) { action in
                    Button { run(action) } label: {
                        Label { Text(action.title) } icon: { Image(systemName: action.symbolName) }
                            .labelStyle(.iconOnly).frame(width: 40, height: 40)
                    }
                    .accessibilityLabel(Text(action.title))
                    .accessibilityIdentifier("editor.selection.\(action.id)")
                }
            }
            .padding(.horizontal, 6)
            .glassEffect(.regular, in: Capsule())
            .scaleEffect(1 / zoom)
            .position(x: min(max(centerX, 120 / zoom), page.pageSize.width - 120 / zoom),
                      y: max(top - 40 / zoom, 28 / zoom))
        }
    }

    private func run(_ action: any SelectionAction) {
        let selection = selection
        Task {
            do { try await action.perform(selection: selection, page: page, editor: session) } catch { session.report(error) }
        }
    }

    // MARK: Gestures

    private func moveGesture(bounds: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .local)
            .onChanged { value in
                beginLiftIfNeeded()
                selection.livePreviewTransform = SelectionGeometry.translation(dx: value.translation.width, dy: value.translation.height)
            }
            .onEnded { _ in commit() }
    }

    private func scaleGesture(bounds: CGRect, corner: Int) -> some Gesture {
        let all = SelectionGeometry.corners(of: bounds, under: .identity)
        let anchor = all[(corner + 2) % 4]
        return DragGesture(minimumDistance: 1, coordinateSpace: .local)
            .onChanged { value in
                beginLiftIfNeeded()
                selection.livePreviewTransform = SelectionGeometry.scale(about: anchor, from: value.startLocation, to: value.location)
            }
            .onEnded { _ in commit() }
    }

    private func rotateGesture(bounds: CGRect) -> some Gesture {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        return DragGesture(minimumDistance: 1, coordinateSpace: .local)
            .onChanged { value in
                beginLiftIfNeeded()
                selection.livePreviewTransform = SelectionGeometry.rotation(about: center, from: value.startLocation, to: value.location)
            }
            .onEnded { _ in commit() }
    }

    private func beginLiftIfNeeded() {
        dragActive = true
        guard lift == nil, !selection.strokeIDs.isEmpty else { return }
        let screen = page.container?.window?.windowScene?.screen.scale ?? 2
        let scale = min(max(session.zoomScale, 1) * screen, 4)
        lift = page.beginLift(strokeIDs: selection.strokeIDs, scale: scale)
    }

    private func commit() {
        let transform = selection.livePreviewTransform
        page.endLift()
        lift = nil
        selection.livePreviewTransform = .identity
        dragActive = false
        guard transform != .identity else { return }
        do { try session.transformer.apply(transform, to: selection, in: page) } catch { session.report(error) }
    }

    /// A drag that ended without `onEnded` (system cancellation) must not leave strokes hidden.
    private func finishLiftIfNeeded() {
        guard lift != nil || page.isLifted else { return }
        page.endLift()
        lift = nil
        selection.livePreviewTransform = .identity
    }
}
