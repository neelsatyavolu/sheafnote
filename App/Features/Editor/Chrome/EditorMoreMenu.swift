import SwiftUI
import UIKit
import SheafnoteCore

/// The "more" menu: the editor's own entries (add page, template, scroll direction, finger drawing, tabs, windows)
/// followed by every registered `NotebookMenuItem`, grouped share / view / insert / tools.
struct EditorMoreMenu: View {
    let session: NotebookSession
    let allowsTabs: Bool
    let compact: Bool

    private var kind: NotebookKind { session.notebook.kind }

    var body: some View {
        Menu {
            pageSection
            viewSection
            registeredSections
            if allowsTabs { windowSection }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel(Text("More", tableName: "Editor"))
        .accessibilityIdentifier("editor.more")
    }

    // MARK: Editor's own entries

    @ViewBuilder private var pageSection: some View {
        Section {
            Button { present { AddPageSheet(session: session) } } label: {
                Label { Text("Add Page…", tableName: "Editor") } icon: { Image(systemName: "plus.rectangle.on.rectangle") }
            }
            .accessibilityIdentifier("editor.more.addPage")
            Button { present { ChangeTemplateSheet(session: session) } } label: {
                Label { Text("Page Template…", tableName: "Editor") } icon: { Image(systemName: "square.grid.3x3") }
            }
            .accessibilityIdentifier("editor.more.template")
        }
    }

    @ViewBuilder private var viewSection: some View {
        Section {
            Picker(selection: Binding(get: { session.scrollDirection }, set: { session.setScrollDirection($0) })) {
                Label { Text("Vertical Scrolling", tableName: "Editor") } icon: { Image(systemName: "arrow.up.and.down") }
                    .tag(ScrollDirection.vertical)
                Label { Text("Horizontal Pages", tableName: "Editor") } icon: { Image(systemName: "arrow.left.and.right") }
                    .tag(ScrollDirection.horizontal)
            } label: { Text("Scroll Direction", tableName: "Editor") }
            Toggle(isOn: Binding(get: { session.toolState.inputMode == .anyInput },
                                 set: { session.toolState.inputMode = $0 ? .anyInput : .pencilOnly })) {
                Label { Text("Draw with Finger", tableName: "Editor") } icon: { Image(systemName: "hand.draw") }
            }
            .accessibilityIdentifier("editor.more.fingerDrawing")
            if compact { compactBarItems }
        }
    }

    @ViewBuilder private var compactBarItems: some View {
        let items = session.host.notebookMenu.barItems.filter { $0.kinds.contains(kind) }.sorted { $0.slot.order < $1.slot.order }
        ForEach(items) { $0.makeView(session) }
    }

    @ViewBuilder private var registeredSections: some View {
        let items = session.host.notebookMenu.menuItems.filter { $0.kinds.contains(kind) }
        ForEach([NotebookMenuGroup.share, .view, .insert, .tools], id: \.rawValue) { group in
            let inGroup = items.filter { $0.group == group }.sorted { $0.order < $1.order }
            if !inGroup.isEmpty {
                Section {
                    ForEach(inGroup) { item in
                        Button { item.perform(session) } label: {
                            Label { Text(item.title) } icon: { Image(systemName: item.symbolName) }
                        }
                        .disabled(!item.isEnabled(session))
                        .accessibilityIdentifier("editor.menu.\(item.id)")
                    }
                }
            }
        }
    }

    @ViewBuilder private var windowSection: some View {
        Section {
            Button { present { NotebookPickerSheet(session: session) } } label: {
                Label { Text("Open Notebook in Tab…", tableName: "Editor") } icon: { Image(systemName: "plus.square.on.square") }
            }
            Button { openInNewWindow() } label: {
                Label { Text("Open in New Window", tableName: "Editor") } icon: { Image(systemName: "macwindow.badge.plus") }
            }
        }
    }

    private func present<Content: View>(detents: Set<PresentationDetent> = [.medium, .large], _ content: @escaping () -> Content) {
        session.present(EditorSheet(detents: detents) { AnyView(content()) })
    }

    private func openInNewWindow() {
        session.flushAll()
        let activity = EditorWindowActivity.userActivity(for: session.notebook.id)
        UIApplication.shared.requestSceneSessionActivation(nil, userActivity: activity, options: nil) { error in
            Task { @MainActor in session.report(error) }
        }
    }
}

/// `NSUserActivity` used to open a notebook in a second window (Stage Manager, Split View).
enum EditorWindowActivity {
    static let type = "co.xanom.sheafnote.openNotebook"
    private static let idKey = "notebookID"

    static func userActivity(for notebookID: UUID) -> NSUserActivity {
        let activity = NSUserActivity(activityType: type)
        activity.userInfo = [idKey: notebookID.uuidString]
        return activity
    }

    static func notebookID(from activity: NSUserActivity) -> UUID? {
        (activity.userInfo?[idKey] as? String).flatMap(UUID.init(uuidString:))
    }
}
