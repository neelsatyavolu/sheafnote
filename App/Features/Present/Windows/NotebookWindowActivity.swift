import SwiftUI
import SheafnoteCore
import UIKit

enum NotebookWindowError: LocalizedError {
    case multipleWindowsUnavailable
    case activationFailed(String)

    var errorDescription: String? {
        switch self {
        case .multipleWindowsUnavailable:
            String(localized: "This device can't show more than one Sheafnote window.", table: "Present")
        case .activationFailed(let reason):
            String(localized: "The new window couldn't be opened. \(reason)", table: "Present")
        }
    }
}

/// Opening a notebook in its own window (Stage Manager, Split View) travels as an `NSUserActivity` on a new scene.
enum NotebookWindowActivity {
    static let type = "co.xanom.sheafnote.open-notebook"
    static let notebookIDKey = "notebookID"

    static func make(notebookID: UUID, title: String) -> NSUserActivity {
        let activity = NSUserActivity(activityType: type)
        activity.title = title
        activity.userInfo = [notebookIDKey: notebookID.uuidString]
        activity.isEligibleForHandoff = false
        return activity
    }

    static func notebookID(from activity: NSUserActivity) -> UUID? {
        guard activity.activityType == type, let raw = activity.userInfo?[notebookIDKey] as? String else { return nil }
        return UUID(uuidString: raw)
    }

    @MainActor
    static func openInNewWindow(_ notebook: Notebook) throws {
        guard UIApplication.shared.supportsMultipleScenes else { throw NotebookWindowError.multipleWindowsUnavailable }
        let activity = make(notebookID: notebook.id, title: notebook.title)
        UIApplication.shared.requestSceneSessionActivation(nil, userActivity: activity, options: nil) { error in
            Task { @MainActor in
                // The library has no hook for asynchronous failures, so surface it with an alert on the active window.
                AlertPresenter.show(NotebookWindowError.activationFailed(error.localizedDescription))
            }
        }
    }
}

/// Minimal alert for failures that happen after a library action has already returned.
@MainActor
enum AlertPresenter {
    static func show(_ error: LocalizedError) {
        guard let scene = ZoomPanelPresenter.activeWindowScene(),
              let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController else { return }
        var top = root
        while let next = top.presentedViewController { top = next }
        let alert = UIAlertController(title: String(localized: "Something went wrong", table: "Present"),
                                      message: error.errorDescription, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: String(localized: "OK", table: "Present"), style: .default))
        top.present(alert, animated: true)
    }
}

/// Opens the notebook named by an incoming window activity above the library in the new scene.
struct NotebookWindowActivityHandler: ViewModifier {
    let host: FeatureHost
    @State private var target: OpenRequest?

    struct OpenRequest: Identifiable { let id: UUID }

    func body(content: Content) -> some View {
        content
            .onContinueUserActivity(NotebookWindowActivity.type) { activity in
                if let id = NotebookWindowActivity.notebookID(from: activity) { target = OpenRequest(id: id) }
            }
            .fullScreenCover(item: $target) { request in
                OpenedNotebookView(notebookID: request.id)
                    .environment(host)
                    .environment(host.services)
            }
    }
}

extension View {
    /// Handles "Open in New Window" activities. Apply inside the root once the feature host is ready.
    func handlesNotebookWindowActivity(host: FeatureHost) -> some View {
        modifier(NotebookWindowActivityHandler(host: host))
    }
}
