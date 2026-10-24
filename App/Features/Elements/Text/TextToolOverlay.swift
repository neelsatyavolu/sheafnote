import SwiftUI
import SheafnoteCore

/// Overlay of the text tool on one page: taps create or edit boxes, and the box being edited is drawn here, above
/// the ink, with a grip to move it and a grip to resize it.
struct TextToolOverlay: View {
    let page: any PageContext
    let editor: EditorContext
    let host: FeatureHost
    let session: TextEditSession

    @State private var dragStart: CGRect?
    private let space = "elements.text.overlay"

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
                .contentShape(Rectangle())
                .gesture(SpatialTapGesture().onEnded { handleTap(at: $0.location) })
            if session.isEditing(on: page.pageID) { editingBox }
        }
        .coordinateSpace(name: space)
        .frame(width: page.pageSize.width, height: page.pageSize.height, alignment: .topLeading)
    }

    // MARK: Editing box

    private var boxHeight: CGFloat {
        TextBoxLayout.fittedHeight(contentHeight: TextStyling.contentHeight(for: session.working, width: session.frame.width),
                                   current: session.frame.height)
    }

    @ViewBuilder
    private var editingBox: some View {
        let frame = session.frame
        let height = boxHeight
        let zoom = max(page.zoomScale, 0.05)
        let grip = 28 / zoom
        TextBoxEditingView(session: session)
            .frame(width: frame.width, height: height)
            .overlay(Rectangle().strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 1.5 / zoom, dash: [5 / zoom, 3 / zoom])))
            .position(x: frame.midX, y: frame.minY + height / 2)
        gripView(symbol: "arrow.up.and.down.and.arrow.left.and.right", size: grip,
                 label: String(localized: "Move text box", table: "Elements"))
            .position(x: frame.minX - grip * 0.1, y: frame.minY - grip * 0.1)
            .gesture(moveGesture(frame))
        gripView(symbol: "arrow.up.left.and.arrow.down.right", size: grip,
                 label: String(localized: "Resize text box", table: "Elements"))
            .position(x: frame.maxX + grip * 0.1, y: frame.minY + height + grip * 0.1)
            .gesture(resizeGesture(frame))
    }

    private func gripView(symbol: String, size: CGFloat, label: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.5))
            .foregroundStyle(Color.accentColor)
            .frame(width: size, height: size)
            .background(Circle().fill(Color.white))
            .overlay(Circle().stroke(Color.accentColor, lineWidth: size / 14))
            .contentShape(Circle())
            .accessibilityLabel(Text(label))
            .accessibilityAddTraits(.isButton)
    }

    private func moveGesture(_ frame: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named(space))
            .onChanged { value in
                let start = dragStart ?? frame
                dragStart = start
                session.frame = clamped(start.offsetBy(dx: value.translation.width, dy: value.translation.height))
            }
            .onEnded { _ in dragStart = nil }
    }

    private func resizeGesture(_ frame: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named(space))
            .onChanged { value in
                let start = dragStart ?? frame
                dragStart = start
                let width = max(start.width + value.translation.width, TextBoxLayout.minimumSize.width)
                let height = max(start.height + value.translation.height, TextBoxLayout.minimumSize.height)
                session.frame = clamped(CGRect(x: start.minX, y: start.minY, width: width, height: height))
            }
            .onEnded { _ in dragStart = nil }
    }

    /// Keeps at least the box's top-left corner area on the page so it can always be grabbed again.
    private func clamped(_ rect: CGRect) -> CGRect {
        let size = page.pageSize
        let x = min(max(rect.minX, 0), max(size.width - 24, 0))
        let y = min(max(rect.minY, 0), max(size.height - 24, 0))
        return CGRect(x: x, y: y, width: rect.width, height: rect.height)
    }

    // MARK: Taps

    private func handleTap(at point: CGPoint) {
        if session.isEditing {
            // The first tap away from a box finishes the edit; a second tap starts the next one.
            TextEditing.commit(session, editor: editor)
            return
        }
        editor.selection.clear()
        if let existing = ElementSelecting.topElement(at: point, on: page, host: host, kinds: [.text]) {
            session.begin(existing: existing, on: page)
        } else {
            session.beginNew(at: point, style: TextDefaultsStore.load(), on: page)
        }
    }
}
