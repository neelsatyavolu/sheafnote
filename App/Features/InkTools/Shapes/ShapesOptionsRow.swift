import SwiftUI
import SheafnoteCore

/// The shapes tool's options row: which shape (or auto), outline colour, line width, fill.
struct ShapesOptionsRow: View {
    let settings: InkToolsSettings
    @State private var showFill = false

    var body: some View {
        let shape = settings.shape
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                modeMenu(shape.mode)
                OptionsDivider()
                ForEach(InkPalette.colors) { swatch($0, selected: $0.hex == shape.strokeHex) }
                ColorPicker(selection: Binding(get: { Color(hex: shape.strokeHex) },
                                               set: { color in settings.updateShape { $0.strokeHex = color.hexString } }),
                            supportsOpacity: false) { Text("Outline color", tableName: "InkTools") }
                    .labelsHidden()
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel(Text("Custom outline color", tableName: "InkTools"))
                OptionsDivider()
                widthDots(shape.lineWidth)
                OptionsDivider()
                fillButton(shape)
            }
            .padding(.horizontal, 12)
        }
        .optionsCapsule()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Shape options", tableName: "InkTools"))
    }

    // MARK: Mode

    private func modeMenu(_ mode: ShapeMode) -> some View {
        Menu {
            Picker(selection: Binding(get: { settings.shape.mode }, set: { new in settings.updateShape { $0.mode = new } })) {
                ForEach(ShapeMode.allCases, id: \.self) { mode in
                    Label { Text(ShapeNames.title(for: mode)) } icon: { Image(systemName: ShapeNames.symbol(for: mode)) }.tag(mode)
                }
            } label: { Text("Shape", tableName: "InkTools") }
        } label: {
            Image(systemName: ShapeNames.symbol(for: mode)).frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityLabel(Text("Shape type, \(String(localized: ShapeNames.title(for: mode)))", tableName: "InkTools"))
        .accessibilityIdentifier("inktools.shapes.mode")
    }

    // MARK: Colour and width

    private func swatch(_ color: InkPalette.Entry, selected: Bool) -> some View {
        Button { settings.updateShape { $0.strokeHex = color.hex } } label: {
            Circle().fill(Color(hex: color.hex)).frame(width: 26, height: 26)
                .overlay(Circle().strokeBorder(.primary.opacity(0.25), lineWidth: 1))
                .overlay { if selected { Circle().strokeBorder(Color.accentColor, lineWidth: 3).padding(-4) } }
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Outline \(String(localized: color.name))", tableName: "InkTools"))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("inktools.shapes.color.\(color.hex)")
    }

    private func widthDots(_ current: Double) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(InkPalette.lineWidths.enumerated()), id: \.offset) { index, width in
                let selected = abs(current - width) < 0.01
                Button { settings.updateShape { $0.lineWidth = width } } label: {
                    Circle().fill(selected ? Color.accentColor : Color.primary.opacity(0.7))
                        .frame(width: 6 + CGFloat(width) * 2, height: 6 + CGFloat(width) * 2)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(InkPalette.widthName(index)))
                .accessibilityValue(Text("\(Int(width.rounded())) points", tableName: "InkTools"))
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityIdentifier("inktools.shapes.width.\(index)")
            }
        }
    }

    // MARK: Fill

    private func fillButton(_ shape: ShapeToolSettings) -> some View {
        Button { showFill = true } label: {
            ZStack {
                Image(systemName: "drop.fill").opacity(shape.fillHex == nil ? 1 : 0.35)
                if let fill = shape.fillHex { Circle().fill(Color(hex: fill)).frame(width: 18, height: 18) }
            }
            .frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityLabel(Text("Fill", tableName: "InkTools"))
        .accessibilityValue(shape.fillHex == nil ? Text("Off", tableName: "InkTools") : Text("On", tableName: "InkTools"))
        .accessibilityIdentifier("inktools.shapes.fill")
        .popover(isPresented: $showFill) {
            ShapeFillPicker(settings: settings).presentationCompactAdaptation(.popover)
        }
    }
}

/// Fill on or off, and its colour.
struct ShapeFillPicker: View {
    let settings: InkToolsSettings

    var body: some View {
        let fill = settings.shape.fillHex
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: Binding(get: { fill != nil }, set: { on in settings.updateShape { $0.fillHex = on ? ($0.fillHex ?? "#F0A500") : nil } })) {
                Text("Fill closed shapes", tableName: "InkTools")
            }
            .accessibilityIdentifier("inktools.shapes.fillToggle")
            if let fill {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(44)), count: 4), spacing: 4) {
                    ForEach(InkPalette.colors) { color in
                        Button { settings.updateShape { $0.fillHex = color.hex } } label: {
                            Circle().fill(Color(hex: color.hex)).frame(width: 28, height: 28)
                                .overlay(Circle().strokeBorder(.primary.opacity(0.25), lineWidth: 1))
                                .overlay { if color.hex == fill { Circle().strokeBorder(Color.accentColor, lineWidth: 3).padding(-4) } }
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("Fill \(String(localized: color.name))", tableName: "InkTools"))
                        .accessibilityAddTraits(color.hex == fill ? .isSelected : [])
                    }
                }
                ColorPicker(selection: Binding(get: { Color(hex: fill) }, set: { c in settings.updateShape { $0.fillHex = c.hexString } }),
                            supportsOpacity: false) { Text("Custom fill color", tableName: "InkTools") }
            }
        }
        .padding()
        .frame(minWidth: 220)
    }
}

/// Colours and widths offered by the ink tools' own pickers.
enum InkPalette {
    struct Entry: Identifiable {
        let hex: String
        let name: LocalizedStringResource
        var id: String { hex }
    }

    static let colors: [Entry] = [
        Entry(hex: "#1B1B1F", name: LocalizedStringResource("Black", table: "InkTools")),
        Entry(hex: "#2F5BEA", name: LocalizedStringResource("Blue", table: "InkTools")),
        Entry(hex: "#D6336C", name: LocalizedStringResource("Pink", table: "InkTools")),
        Entry(hex: "#2B8A3E", name: LocalizedStringResource("Green", table: "InkTools")),
        Entry(hex: "#E8590C", name: LocalizedStringResource("Orange", table: "InkTools")),
        Entry(hex: "#F0A500", name: LocalizedStringResource("Yellow", table: "InkTools")),
        Entry(hex: "#7048E8", name: LocalizedStringResource("Purple", table: "InkTools")),
        Entry(hex: "#868E96", name: LocalizedStringResource("Gray", table: "InkTools")),
    ]

    static let lineWidths: [Double] = [1.5, 3, 6]

    static func widthName(_ index: Int) -> LocalizedStringResource {
        switch index {
        case 0: LocalizedStringResource("Thin", table: "InkTools")
        case 1: LocalizedStringResource("Medium", table: "InkTools")
        default: LocalizedStringResource("Thick", table: "InkTools")
        }
    }
}
