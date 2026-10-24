import SwiftUI
import SheafnoteCore

/// Options row of the tape tool: tape colors and the "Hide all / Show all" switch for the pages in view.
struct TapeOptionsRow: View {
    let editor: EditorContext
    @AppStorage(TapeSettings.swatchKey) private var swatchID = TapeSettings.defaultSwatchID

    private var pages: [any PageContext] {
        let visible = editor.visiblePages
        if !visible.isEmpty { return visible }
        return editor.currentPage.map { [$0] } ?? []
    }

    var body: some View {
        let allCovering = StudyTape.allCovering(in: pages.flatMap(\.elements.all))
        let hasTape = pages.contains { $0.elements.all.contains { $0.kind == .tape } }
        HStack(spacing: 12) {
            ForEach(StudyTape.swatches) { swatch in swatchButton(swatch) }
            OptionsDivider()
            Button { setAll(revealed: allCovering) } label: {
                Label {
                    allCovering ? Text("Show all", tableName: "Elements") : Text("Hide all", tableName: "Elements")
                } icon: {
                    Image(systemName: allCovering ? "eye" : "eye.slash")
                }
            }
            .disabled(!hasTape)
            .accessibilityIdentifier("elements.tape.toggleAll")
            .accessibilityHint(Text("Applies to the pages on screen", tableName: "Elements"))
            if !hasTape {
                Text("Drag on the page to lay down tape", tableName: "Elements")
                    .font(.footnote).foregroundStyle(Theme.inkMuted).lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .optionsCapsule()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("elements.tape.options")
    }

    private func swatchButton(_ swatch: TapeSwatch) -> some View {
        let selected = swatch.id == swatchID
        return Button { swatchID = swatch.id } label: {
            Circle().fill(Color(hex: swatch.hex))
                .frame(width: 24, height: 24)
                .overlay(Circle().strokeBorder(Theme.ink.opacity(0.18), lineWidth: 1))
                .overlay { if selected { Circle().strokeBorder(Theme.ink, lineWidth: 2).padding(-4) } }
                .overlay { if swatch.style != .solid { Image(systemName: swatch.style == .striped ? "line.diagonal" : "circle.dotted").font(.caption2).foregroundStyle(.white) } }
                .frame(width: 34, height: 34)
        }
        .accessibilityLabel(Text(String(localized: String.LocalizationValue(swatch.name), table: "Elements")))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("elements.tape.swatch.\(swatch.id)")
    }

    /// One undo step for the whole switch.
    private func setAll(revealed: Bool) {
        let manager = editor.undoManager
        manager.beginUndoGrouping()
        defer { manager.endUndoGrouping() }
        for page in pages {
            for changed in StudyTape.settingRevealed(revealed, in: page.elements.all) {
                do {
                    let payload = changed.payload
                    try page.elements.update(id: changed.id, undoName: revealed ? LocalizedStringResource("Show All Tape", table: "Elements")
                                                                               : LocalizedStringResource("Hide All Tape", table: "Elements")) {
                        $0.payload = payload
                    }
                } catch {
                    ElementErrors.report(error, editor: editor)
                    return
                }
            }
        }
    }
}
