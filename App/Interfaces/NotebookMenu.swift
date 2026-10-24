import SwiftUI
import SheafnoteCore

/// Beside back/thumbnails (leading) or undo/redo (trailing).
enum EditorBarSlot: Sendable {
    case leading(order: Int)
    case trailing(order: Int)

    var order: Int {
        switch self {
        case .leading(let o), .trailing(let o): o
        }
    }
    var isLeading: Bool {
        if case .leading = self { return true }
        return false
    }
}

struct EditorBarItem: Identifiable {
    let id: String
    let slot: EditorBarSlot
    let kinds: Set<NotebookKind>
    /// A Button/Menu with label and accessibility already set.
    let makeView: @MainActor (EditorContext) -> AnyView
}

/// Groups inside the "more" menu, in this order.
enum NotebookMenuGroup: Int, Sendable { case share, view, insert, tools }

struct NotebookMenuItem: Identifiable {
    let id: String
    let group: NotebookMenuGroup
    let order: Int
    let kinds: Set<NotebookKind>
    let title: LocalizedStringResource
    let symbolName: String
    let isEnabled: @MainActor (EditorContext) -> Bool
    let perform: @MainActor (EditorContext) -> Void
}

/// Thumbnail grid context menu and multi-select toolbar.
struct PageMenuItem: Identifiable {
    let id: String
    let order: Int
    let title: LocalizedStringResource
    let symbolName: String
    let perform: @MainActor ([UUID], EditorContext) async throws -> Void
}

/// Tabs in the page navigator sheet; editor owns "Pages".
struct NavigatorTab: Identifiable {
    let id: String
    let order: Int
    let title: LocalizedStringResource
    let symbolName: String
    let makeView: @MainActor (EditorContext) -> AnyView
}

@MainActor
final class NotebookMenuRegistry {
    private(set) var barItems: [EditorBarItem] = []
    private(set) var menuItems: [NotebookMenuItem] = []
    private(set) var pageMenuItems: [PageMenuItem] = []
    private(set) var navigatorTabs: [NavigatorTab] = []

    func registerBarItem(_ item: EditorBarItem) { barItems.append(item) }
    func registerMenuItem(_ item: NotebookMenuItem) { menuItems.append(item) }
    func registerPageMenuItem(_ item: PageMenuItem) { pageMenuItems.append(item) }
    func registerNavigatorTab(_ tab: NavigatorTab) { navigatorTabs.append(tab) }
}
