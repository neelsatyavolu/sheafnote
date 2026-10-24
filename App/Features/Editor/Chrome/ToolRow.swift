import SwiftUI
import SheafnoteCore

/// The center of the top bar: primary tools from the registry plus a menu for the rest.
struct ToolRow: View {
    let session: NotebookSession

    private var tools: [any EditorTool] { session.host.tools.tools(for: session.notebook.kind) }

    var body: some View {
        let primary = tools.filter { if case .primary = $0.placement { true } else { false } }
        let more = tools.filter { if case .more = $0.placement { true } else { false } }
        HStack(spacing: 2) {
            ForEach(primary, id: \.id) { tool in button(for: tool) }
            if !more.isEmpty { moreMenu(more) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Tools", tableName: "Editor"))
    }

    private func button(for tool: any EditorTool) -> some View {
        let selected = session.toolState.activeToolID == tool.id
        return Button { session.toolState.select(tool.id) } label: {
            Image(systemName: tool.symbolName)
                .imageScale(.large)
                .frame(minWidth: 44, minHeight: 36)
                .background(Capsule().fill(selected ? Color.accentColor.opacity(0.2) : .clear))
                .foregroundStyle(selected ? Color.accentColor : Color.primary)
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
            Image(systemName: "ellipsis").imageScale(.large).frame(minWidth: 44, minHeight: 36)
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
            if let options { ScrollView(.horizontal, showsIndicators: false) { options.padding(.horizontal, 12) } }
        }
        .frame(maxWidth: .infinity)
        .popover(isPresented: $showPalette) {
            if let options { options.padding().presentationCompactAdaptation(.popover) }
        }
        .onChange(of: session.paletteRequest) { _, _ in showPalette = true }
        .accessibilityIdentifier("editor.options")
    }
}
