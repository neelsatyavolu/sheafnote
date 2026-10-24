import Foundation
import SwiftUI
import SheafnoteCore

/// Ink tools: the lasso (select, move, copy, recolor, convert to text, ...), the shapes tool and shape elements,
/// draw-and-hold snapping with the pen, and the highlighter's "draw straight line" option.
enum InkToolsFeature: FeatureModule {
    static let id = "ink-tools"

    static func register(into host: FeatureHost) {
        let settings = InkToolsSettings(store: host.services.settings)
        let clipboard = ClipboardService(host: host)

        host.tools.register(ShapesTool(settings: settings))
        host.tools.register(LassoTool(host: host, settings: settings, clipboard: clipboard))
        host.elementRenderers.register(ShapeElementRenderer())

        for action in InkSelectionActions.make(host: host, clipboard: clipboard) { host.selectionActions.register(action) }

        host.touchObservers.register(DrawAndHoldObserver(settings: settings))
        host.touchObservers.register(StraightHighlighterObserver(settings: settings))
        // The accessory registry is process-wide, so hosted unit tests (which build many hosts) skip it rather than stack
        // up duplicates that would change what the editor's own tests see.
        if !runsUnderUnitTests {
            EditorOptionsAccessories.register(for: .highlighter) { _ in AnyView(StraightLineToggle(settings: settings)) }
        }

        host.settings.register(InkToolsSettingsSection.section(settings: settings))
    }
}

private var runsUnderUnitTests: Bool {
    let env = ProcessInfo.processInfo.environment
    return env["XCTestConfigurationFilePath"] != nil || env["XCTestBundlePath"] != nil
}

/// The highlighter's "draw straight line" switch, appended to its options row.
struct StraightLineToggle: View {
    let settings: InkToolsSettings

    var body: some View {
        let on = settings.straightHighlighter
        Button { settings.setStraightHighlighter(!on) } label: {
            Image(systemName: "line.diagonal")
                .foregroundStyle(on ? Theme.accent : Theme.inkMuted)
                .frame(minWidth: 44, minHeight: 44)
                .background { if on { Circle().fill(Theme.accent.opacity(0.15)).frame(width: 38, height: 38) } }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Draw straight lines", tableName: "InkTools"))
        .accessibilityValue(on ? Text("On", tableName: "InkTools") : Text("Off", tableName: "InkTools"))
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier("inktools.highlighter.straight")
    }
}

/// Settings section "Drawing aids" (order 12, next to Pencil & gestures).
enum InkToolsSettingsSection {
    static func section(settings: InkToolsSettings) -> SettingsSection {
        SettingsSection(id: "ink-tools", order: 12, title: LocalizedStringResource("Drawing Aids", table: "InkTools"),
                        symbolName: "scribble.variable") { _ in
            AnyView(InkToolsSettingsContent(settings: settings))
        }
    }
}

private struct InkToolsSettingsContent: View {
    let settings: InkToolsSettings

    var body: some View {
        Section {
            Toggle(isOn: Binding(get: { settings.drawAndHold }, set: { settings.setDrawAndHold($0) })) {
                Text("Draw and Hold to Snap", tableName: "InkTools")
            }
            .accessibilityIdentifier("settings.inktools.drawAndHold")
            Toggle(isOn: Binding(get: { settings.straightHighlighter }, set: { settings.setStraightHighlighter($0) })) {
                Text("Highlighter Draws Straight Lines", tableName: "InkTools")
            }
            .accessibilityIdentifier("settings.inktools.straightHighlighter")
        } header: {
            Text("Drawing Aids", tableName: "InkTools")
        } footer: {
            Text("With Draw and Hold, pause the Pencil at the end of a stroke and it snaps to the line, circle, rectangle or other shape you drew. Undo brings your own stroke back.", tableName: "InkTools")
        }
    }
}
