import OSLog
import SwiftUI
import UIKit
import SheafnoteCore

/// Moves the reader to a page or notebook: from a search result (the library opens the notebook, then this jumps),
/// and from a link inside an open notebook. The editor's tab model decides which notebook is showing.
@MainActor
enum NotebookNavigator {
    private static let log = Logger(subsystem: "co.xanom.sheafnote", category: "search.navigation")

    /// The editor of a notebook that is open right now, if any.
    static func openEditor(for notebookID: UUID, host: FeatureHost) -> (any EditorContext)? {
        guard EditorTabs.shared.openIDs.contains(notebookID),
              let notebook = host.services.library.notebook(id: notebookID) else { return nil }
        return EditorTabs.shared.session(for: notebook, host: host, sizing: .fixed(.zero))
    }

    /// Waits for a freshly opened notebook to finish laying out, then scrolls to the page. Gives up quietly after a
    /// few seconds; the notebook is open at its last position in that case.
    static func goToPage(_ pageID: UUID, in notebookID: UUID, host: FeatureHost) async {
        guard let notebook = host.services.library.notebook(id: notebookID), notebook.kind == .paged else { return }
        for _ in 0..<60 {
            let tabs = EditorTabs.shared
            if tabs.openIDs.contains(notebookID), (tabs.activeID ?? notebookID) == notebookID {
                let session = tabs.session(for: notebook, host: host, sizing: .fixed(.zero))
                if session.viewport != nil {
                    session.goToPage(id: pageID, animated: false)
                    try? await Task.sleep(for: .milliseconds(250))
                    session.goToPage(id: pageID, animated: false)
                    return
                }
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    /// Shows another notebook in the editor's tab strip and, when given, scrolls it to a page.
    static func openInEditor(_ notebookID: UUID, page pageID: UUID?, host: FeatureHost) async {
        guard let notebook = host.services.library.notebook(id: notebookID) else { return }
        do { try host.services.library.recordOpened(notebookID) } catch {
            // Only the "last opened" date is affected; the notebook itself still opens.
            log.error("Could not record opening a notebook: \(error.localizedDescription, privacy: .public)")
        }
        EditorTabs.shared.open(notebook)
        if let pageID { await goToPage(pageID, in: notebookID, host: host) }
    }
}

enum LinkOutcome {
    case done
    case failed(LocalizedStringResource)
}

/// Follows a link target. Used by the link element and available to any element that carries a `LinkTarget`.
@MainActor
enum LinkFollower {
    static func follow(_ target: LinkTarget, from currentNotebookID: UUID, host: FeatureHost) async -> LinkOutcome {
        switch target {
        case .url(let url):
            return await UIApplication.shared.open(url)
                ? .done : .failed(LocalizedStringResource("That link couldn't be opened.", table: "Search"))
        case .page(let pageID):
            return await followPage(pageID, from: currentNotebookID, host: host)
        case .notebook(let notebookID):
            guard let notebook = host.services.library.notebook(id: notebookID), notebook.deletedAt == nil else {
                return .failed(LocalizedStringResource("That notebook is in Recently Deleted or gone.", table: "Search"))
            }
            if notebookID != currentNotebookID { await NotebookNavigator.openInEditor(notebookID, page: nil, host: host) }
            return .done
        }
    }

    private static func followPage(_ pageID: UUID, from currentNotebookID: UUID, host: FeatureHost) async -> LinkOutcome {
        guard let page = host.services.pages.page(id: pageID), page.deletedAt == nil,
              let notebook = host.services.library.notebook(id: page.notebookID), notebook.deletedAt == nil else {
            return .failed(LocalizedStringResource("That page no longer exists.", table: "Search"))
        }
        if notebook.id == currentNotebookID, let editor = NotebookNavigator.openEditor(for: notebook.id, host: host) {
            editor.goToPage(id: pageID, animated: true)
        } else {
            await NotebookNavigator.openInEditor(notebook.id, page: pageID, host: host)
        }
        return .done
    }
}
