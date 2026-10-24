import SwiftUI
import SheafnoteCore

/// Colour, width and (for shapes) fill of the current selection. Each change applies at once as its own undo step.
struct SelectionStyleSheet: View {
    let styler: SelectionStyler
    let hasShapes: Bool
    let hasStrokes: Bool

    @State private var width: Double
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    init(styler: SelectionStyler) {
        self.styler = styler
        let contents = styler.contents
        hasShapes = !(contents?.shapeElements.isEmpty ?? true)
        hasStrokes = !(contents?.strokes.isEmpty ?? true)
        _width = State(initialValue: min(max(contents?.representativeWidth ?? 3, 0.5), 40))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section { colorGrid { hex in apply { try styler.recolor(hex) } } } header: {
                    Text(hasShapes && !hasStrokes ? "Outline color" : "Color", tableName: "InkTools")
                }
                Section {
                    Slider(value: $width, in: 0.5...40, onEditingChanged: { editing in
                        if !editing { apply { try styler.setWidth(width) } }
                    }) { Text("Width", tableName: "InkTools") }
                        .accessibilityValue(Text("\(Int(width.rounded())) points", tableName: "InkTools"))
                        .accessibilityIdentifier("inktools.style.width")
                } header: {
                    Text("Width \(Int(width.rounded())) pt", tableName: "InkTools")
                }
                if hasShapes {
                    Section {
                        Button { apply { try styler.setFill(nil) } } label: { Text("No fill", tableName: "InkTools") }
                            .accessibilityIdentifier("inktools.style.noFill")
                        colorGrid { hex in apply { try styler.setFill(hex) } }
                    } header: {
                        Text("Fill", tableName: "InkTools")
                    }
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }
            }
            .navigationTitle(Text("Style", tableName: "InkTools"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Text("Done", tableName: "InkTools") }
                }
            }
        }
    }

    private func colorGrid(_ choose: @escaping (String) -> Void) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 44)), count: 4), spacing: 4) {
            ForEach(InkPalette.colors) { color in
                Button { choose(color.hex) } label: {
                    Circle().fill(Color(hex: color.hex)).frame(width: 30, height: 30)
                        .overlay(Circle().strokeBorder(.primary.opacity(0.25), lineWidth: 1))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(color.name))
                .accessibilityIdentifier("inktools.style.\(color.hex)")
            }
        }
    }

    private func apply(_ change: () throws -> Void) {
        do {
            try change()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
