import SwiftUI
import SheafnoteCore

/// Options row of the zoom window: where the box sits, how much it magnifies, and how it advances.
struct ZoomOptionsView: View {
    let controller: ZoomWindowController

    var body: some View {
        HStack(spacing: 16) {
            nudgePad
            labeledSlider(
                title: Text("Zoom", tableName: "Present"), id: "magnification",
                value: Binding(get: { Double(controller.model.magnification) }, set: { controller.setMagnification(CGFloat($0)) }),
                range: Double(ZoomWindowModel.magnificationRange.lowerBound)...Double(ZoomWindowModel.magnificationRange.upperBound))
            Toggle(isOn: Binding(get: { controller.model.autoAdvance }, set: { controller.setAutoAdvance($0) })) {
                Text("Auto-advance", tableName: "Present")
            }
            .fixedSize()
            .accessibilityIdentifier("present.zoom.autoAdvance")
            if controller.model.autoAdvance {
                labeledSlider(
                    title: Text("Advance at", tableName: "Present"), id: "trigger",
                    value: Binding(get: { Double(controller.model.triggerFraction) }, set: { controller.setTrigger(CGFloat($0)) }),
                    range: 0.5...0.95)
            }
            marginStepper(title: Text("Left margin", tableName: "Present"), id: "leftMargin",
                          value: Binding(get: { controller.model.leftMargin }, set: { controller.setLeftMargin($0) }))
            marginStepper(title: Text("Right margin", tableName: "Present"), id: "rightMargin",
                          value: Binding(get: { controller.model.rightMargin }, set: { controller.setRightMargin($0) }))
        }
        .padding(.vertical, 2)
    }

    private var nudgePad: some View {
        HStack(spacing: 4) {
            nudge(.left, symbol: "arrow.left", label: Text("Move box left", tableName: "Present"))
            nudge(.up, symbol: "arrow.up", label: Text("Move box up", tableName: "Present"))
            nudge(.down, symbol: "arrow.down", label: Text("Move box down", tableName: "Present"))
            nudge(.right, symbol: "arrow.right", label: Text("Move box right", tableName: "Present"))
        }
    }

    private func nudge(_ direction: NudgeDirection, symbol: String, label: Text) -> some View {
        Button { controller.nudge(direction) } label: { Image(systemName: symbol).frame(width: 32, height: 32) }
            .buttonStyle(.bordered)
            .accessibilityLabel(label)
            .accessibilityIdentifier("present.zoom.nudge.\(symbol)")
    }

    private func labeledSlider(title: Text, id: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack(spacing: 8) {
            title.font(.subheadline)
            Slider(value: value, in: range) { title }
                .frame(width: 120)
                .accessibilityIdentifier("present.zoom.\(id)")
        }
    }

    private func marginStepper(title: Text, id: String, value: Binding<CGFloat>) -> some View {
        Stepper(value: value, in: 0...400, step: 12) {
            HStack(spacing: 6) {
                title.font(.subheadline)
                Text("\(Int(value.wrappedValue))").monospacedDigit().font(.subheadline.weight(.semibold))
            }
        }
        .fixedSize()
        .accessibilityIdentifier("present.zoom.\(id)")
    }
}
