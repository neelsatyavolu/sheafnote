import SwiftUI

/// Routes files from the file importer, drag and drop, and "Open in" to the handler registered for their type.
@MainActor
struct LibraryImporter {
    let session: LibrarySession
    let host: FeatureHost

    @discardableResult
    func handle(_ urls: [URL], folderID: UUID?) -> Bool {
        guard !urls.isEmpty, !host.library.importHandlers.isEmpty else { return false }
        guard let handler = host.library.importHandler(for: urls[0]) else {
            session.alert = LibraryAlert(title: "Can't Import", message: String(localized: "Sheafnote can't import this kind of file."))
            return false
        }
        let matching = urls.filter { host.library.importHandler(for: $0)?.id == handler.id }
        let context = session.actionContext(folderID: folderID)
        Task {
            let scoped = matching.filter { $0.startAccessingSecurityScopedResource() }
            defer { scoped.forEach { $0.stopAccessingSecurityScopedResource() } }
            do { try await handler.handle(matching, context) } catch { session.show(error) }
        }
        return true
    }
}
