import Observation
import SwiftUI
import SheafnoteCore

enum LibraryLayout: String, Codable { case grid, list }

struct PresentedSheet: Identifiable {
    let id = UUID()
    let content: AnyView
}

struct LibraryAlert: Identifiable {
    let id = UUID()
    let title: LocalizedStringResource
    let message: String
}

struct OpenTarget: Identifiable, Hashable { let id: UUID }

/// UI state shared by every library screen in a window: sort, layout, sheets, errors, the open notebook.
@MainActor @Observable
final class LibrarySession {
    let services: AppServices

    var sort: LibrarySort { didSet { services.settings.setLocal(sort, for: "library.sort") } }
    var layout: LibraryLayout { didSet { services.settings.setLocal(layout, for: "library.layout") } }
    var sheet: PresentedSheet?
    var alert: LibraryAlert?
    var openTarget: OpenTarget?
    var isImporterShown = false

    init(services: AppServices) {
        self.services = services
        self.sort = services.settings.local("library.sort", as: LibrarySort.self) ?? LibrarySort()
        self.layout = services.settings.local("library.layout", as: LibraryLayout.self) ?? .grid
    }

    func present(_ view: AnyView) { sheet = PresentedSheet(content: view) }

    func open(_ notebook: Notebook) {
        do {
            try services.library.recordOpened(notebook.id)
        } catch {
            show(error)
        }
        openTarget = OpenTarget(id: notebook.id)
    }

    func show(_ error: Error) {
        alert = LibraryAlert(title: "Something went wrong", message: error.localizedDescription)
    }

    func actionContext(folderID: UUID?) -> LibraryActionContext {
        LibraryActionContext(
            services: services, currentFolderID: folderID,
            present: { [weak self] in self?.present($0) },
            open: { [weak self] in self?.open($0) },
            showError: { [weak self] in self?.show($0) })
    }
}
