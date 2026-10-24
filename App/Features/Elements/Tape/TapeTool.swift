import SwiftUI
import SheafnoteCore

/// Drag to lay down a strip of study tape; tap a tape to hide or reveal it.
@MainActor
final class TapeTool: EditorTool {
    let id = ToolID.tape
    let title = LocalizedStringResource("Study Tape", table: "Elements")
    let symbolName = "bandage"
    let placement = ToolPlacement.more(order: 10)
    let supportedKinds: Set<NotebookKind> = [.paged, .whiteboard]
    let inputPolicy = ToolInputPolicy.overlayCapturesAll

    private unowned let host: FeatureHost

    init(host: FeatureHost) { self.host = host }

    func activate(in editor: EditorContext) { editor.selection.clear() }

    func deactivate(in editor: EditorContext) {}

    func makeOptionsView(in editor: EditorContext) -> AnyView { AnyView(TapeOptionsRow(editor: editor)) }

    func makeOverlay(for page: PageContext, in editor: EditorContext) -> AnyView? {
        AnyView(TapeToolOverlay(page: page, editor: editor, host: host))
    }
}

struct TapeToolOverlay: View {
    let page: any PageContext
    let editor: EditorContext
    let host: FeatureHost

    @AppStorage(TapeSettings.swatchKey) private var swatchID = TapeSettings.defaultSwatchID
    @State private var drag: (start: CGPoint, current: CGPoint)?

    private static let tapSlop: CGFloat = 8

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
                .contentShape(Rectangle())
                .gesture(dragGesture)
            if let drag, let rect = StudyTape.rect(from: drag.start, to: drag.current, pageSize: page.pageSize) {
                TapePreview(rect: rect, swatch: TapeSettings.swatch(id: swatchID))
            }
        }
        .frame(width: page.pageSize.width, height: page.pageSize.height, alignment: .topLeading)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in drag = (value.startLocation, value.location) }
            .onEnded { value in
                drag = nil
                if hypot(value.translation.width, value.translation.height) < Self.tapSlop {
                    toggleTape(at: value.startLocation)
                } else {
                    layTape(from: value.startLocation, to: value.location)
                }
            }
    }

    private func toggleTape(at point: CGPoint) {
        guard let tape = ElementSelecting.topElement(at: point, on: page, host: host, kinds: [.tape]) else { return }
        TapeToggling.toggle(tape, on: page, editor: editor)
    }

    private func layTape(from start: CGPoint, to end: CGPoint) {
        guard let rect = StudyTape.rect(from: start, to: end, pageSize: page.pageSize) else { return }
        let z = TextBoxLayout.nextZIndex(in: page.elements.all)
        let element = StudyTape.element(pageID: page.pageID, rect: rect, swatch: TapeSettings.swatch(id: swatchID), zIndex: z)
        do {
            try page.elements.add(element, undoName: LocalizedStringResource("Add Tape", table: "Elements"))
        } catch {
            ElementErrors.report(error, editor: editor)
        }
    }
}

/// Faint preview of the tape while the drag is in progress.
private struct TapePreview: View {
    let rect: CGRect
    let swatch: TapeSwatch

    var body: some View {
        Canvas { context, size in
            context.withCGContext { cg in
                TapeRenderer.draw(TapePayload(colorHex: swatch.hex, isRevealed: false, style: swatch.style), covering: true, in: cg, size: size)
            }
        }
        .frame(width: rect.width, height: rect.height)
        .opacity(0.7)
        .position(x: rect.midX, y: rect.midY)
        .allowsHitTesting(false)
    }
}

enum TapeSettings {
    static let swatchKey = "elements.tapeSwatch"
    static let defaultSwatchID = StudyTape.swatches[0].id

    static func swatch(id: String) -> TapeSwatch {
        StudyTape.swatches.first { $0.id == id } ?? StudyTape.swatches[0]
    }
}
