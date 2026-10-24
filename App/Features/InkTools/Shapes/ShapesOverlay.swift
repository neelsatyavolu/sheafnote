import SwiftUI
import SheafnoteCore

/// Captures the drag that draws a shape and shows what it will become. Page coordinates (the overlay is page-sized).
struct ShapesOverlay: View {
    let tool: ShapesTool
    let page: any PageContext
    let editor: EditorContext
    let settings: InkToolsSettings

    @State private var path: [CGPoint] = []

    var body: some View {
        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .gesture(drawGesture)
                .accessibilityElement()
                .accessibilityLabel(Text("Shape drawing area", tableName: "InkTools"))
                .accessibilityHint(Text("Draw a shape with the Pencil. Shapes you add stay editable.", tableName: "InkTools"))
            preview.allowsHitTesting(false)
        }
    }

    private var drawGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                if path.isEmpty { editor.selection.clear() }
                if path.count < 4_000 { path.append(value.location) }
            }
            .onEnded { value in
                path.append(value.location)
                let finished = path
                path = []
                tool.commit(finished, page: page, editor: editor)
            }
    }

    @ViewBuilder private var preview: some View {
        let options = settings.shape
        let zoom = max(page.zoomScale, 0.05)
        if path.count > 1 {
            let color = Color(hex: options.strokeHex)
            let figure = options.mode.kind.flatMap { ShapeBuilder.figure(kind: $0, path: path) }
            if let figure {
                let outline = Path(ShapeCGPath.drawingPath(for: figure, lineWidth: CGFloat(options.lineWidth)))
                ZStack {
                    if let fill = options.fillHex, figure.isClosed { outline.fill(Color(hex: fill).opacity(0.5)) }
                    outline.stroke(color, style: StrokeStyle(lineWidth: options.lineWidth, lineCap: .round, lineJoin: .round))
                }
            } else {
                Path { p in
                    p.move(to: path[0])
                    path.dropFirst().forEach { p.addLine(to: $0) }
                }
                .stroke(color.opacity(0.8), style: StrokeStyle(lineWidth: max(options.lineWidth, 1.5 / zoom), lineCap: .round, lineJoin: .round))
            }
        }
    }
}
