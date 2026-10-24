import SwiftUI
import SheafnoteCore

/// Captures the lasso drag and draws its dashed path. Page coordinates (the overlay is page-sized).
struct LassoOverlay: View {
    let tool: LassoTool
    let page: any PageContext
    let editor: EditorContext

    @State private var path: [CGPoint] = []

    var body: some View {
        let zoom = max(page.zoomScale, 0.05)
        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .gesture(dragGesture)
                .accessibilityElement()
                .accessibilityLabel(Text("Lasso area", tableName: "InkTools"))
                .accessibilityHint(Text("Draw a loop around items to select them.", tableName: "InkTools"))
                .accessibilityAction(named: Text("Select everything on this page", tableName: "InkTools")) {
                    tool.selectAll(page: page, editor: editor)
                }
            if path.count > 1 {
                Path { p in
                    p.move(to: path[0])
                    path.dropFirst().forEach { p.addLine(to: $0) }
                    p.closeSubpath()
                }
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1.5 / zoom, lineCap: .round, lineJoin: .round,
                                                              dash: [6 / zoom, 4 / zoom]))
                .allowsHitTesting(false)
            }
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                if path.isEmpty { editor.selection.clear() }
                if path.count < 4_000 { path.append(value.location) }
            }
            .onEnded { value in
                path.append(value.location)
                let finished = path
                path = []
                tool.finish(finished, page: page, editor: editor)
            }
    }
}
