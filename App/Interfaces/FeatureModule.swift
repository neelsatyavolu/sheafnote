import Foundation
import Observation

/// A unit of functionality (editor, sync, ...) that plugs itself into the app through the registries on `FeatureHost`.
@MainActor
protocol FeatureModule {
    static var id: String { get }
    static func register(into host: FeatureHost)
}

/// The registries every feature module registers into. Created once per app launch.
@MainActor @Observable
final class FeatureHost {
    let services: AppServices
    let tools = ToolRegistry()
    let layers = PageLayerRegistry()
    let elementRenderers = ElementRendererRegistry()
    let selectionActions = SelectionActionRegistry()
    let documents = DocumentRouter()
    let library = LibraryMenuRegistry()
    let notebookMenu = NotebookMenuRegistry()
    let settings = SettingsRegistry()
    let touchObservers = InkTouchObserverRegistry()

    init(services: AppServices) {
        self.services = services
    }

    /// Registers foundation's own entries, then every feature module in `FeatureModules.all`.
    func bootstrap() {
        FoundationRegistrations.register(into: self)
        for module in FeatureModules.all { module.register(into: self) }
    }
}
