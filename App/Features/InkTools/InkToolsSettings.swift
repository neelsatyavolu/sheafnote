import Observation
import SheafnoteCore

/// Options of the ink tools, kept on this device. Every change is written straight away.
@MainActor @Observable
final class InkToolsSettings {
    static let lassoKey = "inkTools.lassoFilters"
    static let shapesKey = "inkTools.shapes"
    static let straightKey = "inkTools.straightHighlighter"
    static let holdKey = "inkTools.drawAndHold"

    @ObservationIgnored private let store: AppSettingsStore
    private(set) var lassoFilters: LassoFilters
    private(set) var shape: ShapeToolSettings
    private(set) var straightHighlighter: Bool
    private(set) var drawAndHold: Bool

    init(store: AppSettingsStore) {
        self.store = store
        lassoFilters = store.local(Self.lassoKey, as: LassoFilters.self) ?? .all
        shape = store.local(Self.shapesKey, as: ShapeToolSettings.self) ?? ShapeToolSettings()
        straightHighlighter = store.local(Self.straightKey, as: Bool.self) ?? false
        drawAndHold = store.local(Self.holdKey, as: Bool.self) ?? true
    }

    func setLassoFilters(_ filters: LassoFilters) {
        lassoFilters = filters
        store.setLocal(filters, for: Self.lassoKey)
    }

    func toggleLassoFilter(_ filter: LassoFilters) {
        var next = lassoFilters
        if next.contains(filter) { next.remove(filter) } else { next.insert(filter) }
        setLassoFilters(next)
    }

    func updateShape(_ change: (inout ShapeToolSettings) -> Void) {
        var next = shape
        change(&next)
        shape = next
        store.setLocal(next, for: Self.shapesKey)
    }

    func setStraightHighlighter(_ on: Bool) {
        straightHighlighter = on
        store.setLocal(on, for: Self.straightKey)
    }

    func setDrawAndHold(_ on: Bool) {
        drawAndHold = on
        store.setLocal(on, for: Self.holdKey)
    }
}
