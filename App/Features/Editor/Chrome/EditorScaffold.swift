import SwiftUI
import SheafnoteCore

/// The notebook editor chrome: top bar (back, thumbnails, tool row, undo/redo, more), the slim options row, and the
/// zoomable page canvas on a gray background. On iPhone the tool row moves to a bottom toolbar.
/// `sizing` lets the whiteboard unit reuse everything with an infinite page.
struct EditorScaffold: View {
    let notebook: Notebook
    let host: FeatureHost
    var sizing: PageSizing = .fixed(.zero)
    var allowsTabs = false
    var onClose: (() -> Void)?

    @State private var session: NotebookSession
    @State private var token = UUID()
    @State private var claimed: Bool?
    @State private var showGoTo = false
    @State private var goToText = ""
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    init(notebook: Notebook, host: FeatureHost, sizing: PageSizing = .fixed(.zero), allowsTabs: Bool = false,
         onClose: (() -> Void)? = nil) {
        self.notebook = notebook
        self.host = host
        self.sizing = sizing
        self.allowsTabs = allowsTabs
        self.onClose = onClose
        _session = State(initialValue: EditorTabs.shared.session(for: notebook, host: host, sizing: sizing))
    }

    private var compact: Bool { sizeClass == .compact }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGray5).ignoresSafeArea()
                if claimed == true {
                    NotebookCanvasHost(session: session).ignoresSafeArea()
                    EditorOverlays(session: session, showGoTo: $showGoTo)
                } else if claimed == false {
                    ContentUnavailableView {
                        Label { Text("Open in Another Window", tableName: "Editor") } icon: { Image(systemName: "macwindow.on.rectangle") }
                    } description: {
                        Text("This notebook is already open in another window. Close it there to work on it here.", tableName: "Editor")
                    }
                }
            }
            .safeAreaInset(edge: compact ? .bottom : .top, spacing: 0) {
                OptionsRowHost(session: session).padding(.vertical, 6)
            }
            .toolbar { toolbarContent }
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden()
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("editor.root")
        }
        .sheet(item: $session.sheet) { sheet in
            sheet.content().presentationDetents(sheet.detents)
        }
        .alert(item: $session.alert) { alert in
            Alert(title: Text("Something went wrong", tableName: "Editor"), message: Text(alert.message),
                  dismissButton: .default(Text("OK", tableName: "Editor")))
        }
        .alert(Text("Go to Page", tableName: "Editor"), isPresented: $showGoTo) {
            TextField(text: $goToText) { Text("Page number", tableName: "Editor") }.keyboardType(.numberPad)
            Button { if let n = Int(goToText) { session.goToPage(number: n) }; goToText = "" } label: { Text("Go", tableName: "Editor") }
            Button(role: .cancel) { goToText = "" } label: { Text("Cancel", tableName: "Editor") }
        } message: {
            Text("This notebook has \(session.pageIDs.count) pages.", tableName: "Editor")
        }
        .onChange(of: scenePhase) { _, phase in if phase != .active { session.flushAll() } }
        .onAppear { claimed = EditorTabs.shared.claim(notebook.id, token: token) }
        .onDisappear {
            UnsavedInkKeeper.shared.settle(session)
            EditorTabs.shared.release(notebook.id, token: token)
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarLeading) {
            Button { close() } label: { Image(systemName: "chevron.backward") }
                .accessibilityLabel(Text("Back to library", tableName: "Editor"))
                .accessibilityIdentifier("editor.back")
            Button { openNavigator() } label: { Image(systemName: "square.grid.2x2") }
                .accessibilityLabel(Text("Pages", tableName: "Editor"))
                .accessibilityIdentifier("editor.pages")
            if !compact { barItems(leading: true) }
        }
        if !compact {
            ToolbarItem(placement: .principal) { ToolRow(session: session) }
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            if !compact { barItems(leading: false) }
            Button { session.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                .disabled(!session.canUndo)
                .keyboardShortcut("z", modifiers: .command)
                .accessibilityLabel(Text("Undo", tableName: "Editor"))
                .accessibilityIdentifier("editor.undo")
            Button { session.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                .disabled(!session.canRedo)
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .accessibilityLabel(Text("Redo", tableName: "Editor"))
                .accessibilityIdentifier("editor.redo")
            EditorMoreMenu(session: session, allowsTabs: allowsTabs, compact: compact)
        }
        if compact {
            ToolbarItemGroup(placement: .bottomBar) { ToolRow(session: session) }
        }
    }

    @ViewBuilder
    private func barItems(leading: Bool) -> some View {
        let items = host.notebookMenu.barItems
            .filter { $0.kinds.contains(notebook.kind) && $0.slot.isLeading == leading }
            .sorted { $0.slot.order < $1.slot.order }
        ForEach(items) { $0.makeView(session) }
    }

    private func close() {
        guard session.flushAll() else {
            session.alert = EditorAlert(message: String(
                localized: "Your latest writing could not be saved yet. Stay on this page while Sheafnote keeps trying; the ink is still on screen and nothing has been lost.",
                table: "Editor"))
            return
        }
        if let onClose { onClose() } else { dismiss() }
    }

    private func openNavigator() {
        session.flushAll()
        session.present(EditorSheet(detents: [.large]) { AnyView(PageNavigatorSheet(session: session)) })
    }
}
