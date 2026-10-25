import SwiftUI
import SheafnoteCore

/// The center of the top bar: primary tools from the registry plus a menu for the rest. Stacks vertically when the
/// system puts bars at the side of the display (iPhone Duo's outer display).
struct ToolRow: View {
    let session: NotebookSession
    @State private var bounces: [ToolID: Int] = [:]
    @Environment(\.colorScheme) private var scheme
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var tools: [any EditorTool] { session.host.tools.tools(for: session.notebook.kind) }

    var body: some View {
        let primary = tools.filter { if case .primary = $0.placement { true } else { false } }
        let more = tools.filter { if case .more = $0.placement { true } else { false } }
        BarStack(spacing: sizeClass == .compact ? 0 : 2) {
            ForEach(primary, id: \.id) { tool in button(for: tool) }
            if !more.isEmpty { moreMenu(more) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Tools", tableName: "Editor"))
        .onChange(of: session.toolState.activeToolID) { _, new in
            Haptics.selection()
            if !reduceMotion { bounces[new, default: 0] += 1 }
        }
    }

    /// The current ink color for pen and highlighter; the accent for tools without one.
    private func tint(for tool: any EditorTool) -> Color {
        let store = session.presetStore
        guard tool.id == .pen || tool.id == .highlighter, let hex = store.selectedPreset(for: tool.id)?.colorHex else { return Theme.accent }
        return Color(hex: hex).legible(on: scheme)
    }

    private func button(for tool: any EditorTool) -> some View {
        let selected = session.toolState.activeToolID == tool.id
        let tint = tint(for: tool)
        return Button { session.toolState.select(tool.id) } label: {
            Image(systemName: tool.symbolName)
                .imageScale(.large)
                .symbolEffect(.bounce, options: .nonRepeating, value: bounces[tool.id, default: 0])
                .frame(minWidth: sizeClass == .compact ? 36 : 44, minHeight: 36)
                .background(Capsule().fill(selected ? tint.opacity(0.18) : .clear))
                .overlay(alignment: .bottom) {
                    if selected { Circle().fill(tint).frame(width: 4, height: 4).offset(y: 1) }
                }
                .foregroundStyle(selected ? tint : Theme.inkMuted)
        }
        .accessibilityLabel(Text(tool.title))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("editor.tool.\(tool.id.rawValue)")
    }

    private func moreMenu(_ tools: [any EditorTool]) -> some View {
        Menu {
            ForEach(tools, id: \.id) { tool in
                Button { session.toolState.select(tool.id) } label: {
                    Label { Text(tool.title) } icon: { Image(systemName: tool.symbolName) }
                }
            }
        } label: {
            Image(systemName: "ellipsis").imageScale(.large).foregroundStyle(Theme.inkMuted).frame(minWidth: sizeClass == .compact ? 36 : 44, minHeight: 36)
        }
        .accessibilityLabel(Text("More tools", tableName: "Editor"))
        .accessibilityIdentifier("editor.tool.more")
    }
}

/// The slim second row: the selected tool's options. Pencil squeeze ("show palette") opens the same controls as a popover.
struct OptionsRowHost: View {
    let session: NotebookSession
    @State private var showPalette = false

    var body: some View {
        let options = session.activeTool?.makeOptionsView(in: session)
        HStack {
            if let options {
                ScrollView(.horizontal, showsIndicators: false) { options.padding(.horizontal, 12) }
                    .scrollBounceBehavior(.basedOnSize)
            }
        }
        .frame(maxWidth: .infinity)
        .popover(isPresented: $showPalette) {
            if let options { options.padding().presentationCompactAdaptation(.popover) }
        }
        .onChange(of: session.paletteRequest) { _, _ in showPalette = true }
        .accessibilityIdentifier("editor.options")
    }
}
