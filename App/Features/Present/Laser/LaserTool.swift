import SwiftUI
import SheafnoteCore

/// Dot and fading trail for presenting. It captures every touch on the page (so a finger works too) and never
/// touches the page's ink.
@MainActor
final class LaserTool: EditorTool {
    let id = ToolID.laser
    let title = LocalizedStringResource("Laser Pointer", table: "Present")
    let symbolName = "dot.radiowaves.left.and.right"
    let placement = ToolPlacement.primary(order: 80)
    let supportedKinds: Set<NotebookKind> = [.paged, .whiteboard]
    let inputPolicy = ToolInputPolicy.overlayCapturesAll

    func deactivate(in editor: EditorContext) {
        LaserController.controller(for: editor.notebook.id).reset()
    }

    func makeOptionsView(in editor: EditorContext) -> AnyView {
        AnyView(LaserOptionsView(controller: LaserController.controller(for: editor.notebook.id)))
    }

    func makeOverlay(for page: PageContext, in editor: EditorContext) -> AnyView? {
        AnyView(LaserOverlay(page: page, controller: LaserController.controller(for: editor.notebook.id)))
    }
}

struct LaserOptionsView: View {
    let controller: LaserController

    var body: some View {
        HStack(spacing: 14) {
            Picker(selection: Binding(get: { controller.style }, set: { controller.setStyle($0) })) {
                Text("Trail", tableName: "Present").tag(LaserTrailModel.Style.trail)
                Text("Dot", tableName: "Present").tag(LaserTrailModel.Style.dot)
            } label: { Text("Laser style", tableName: "Present") }
                .pickerStyle(.segmented)
                .frame(width: 150)
                .accessibilityIdentifier("present.laser.style")
            HStack(spacing: 2) {
                ForEach(LaserController.palette) { swatch in
                    let selected = controller.colorID == swatch.id
                    Button { controller.setColor(swatch.id) } label: {
                        ZStack {
                            Circle().fill(swatch.color).frame(width: 24, height: 24)
                            Circle().strokeBorder(Color.primary, lineWidth: selected ? 2.5 : 0).frame(width: 32, height: 32)
                        }
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(swatch.name))
                    .accessibilityValue(selected ? Text("Selected", tableName: "Present") : Text(verbatim: ""))
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    .accessibilityIdentifier("present.laser.color.\(swatch.id)")
                }
            }
            HStack(spacing: 6) {
                Image(systemName: "circle.fill").imageScale(.small).accessibilityHidden(true)
                Slider(value: Binding(get: { controller.diameter }, set: { controller.setDiameter($0) }), in: 8...40) { Text("Laser size", tableName: "Present") }
                    .frame(width: 120)
                    .accessibilityIdentifier("present.laser.size")
                Image(systemName: "circle.fill").imageScale(.large).accessibilityHidden(true)
            }
        }
        .padding(.vertical, 2)
    }
}
