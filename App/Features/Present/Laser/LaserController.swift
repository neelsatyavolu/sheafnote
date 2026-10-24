import Observation
import SwiftUI
import SheafnoteCore

/// Live state of one notebook's laser pointer. The laser never writes ink; the overlay and the presentation mirror
/// both read this model.
@MainActor @Observable
final class LaserController {
    private static var controllers: [UUID: LaserController] = [:]

    static func controller(for notebookID: UUID) -> LaserController {
        if let existing = controllers[notebookID] { return existing }
        let created = LaserController()
        controllers[notebookID] = created
        return created
    }

    static let palette: [LaserColor] = LaserColor.all

    private(set) var model = LaserTrailModel()
    private(set) var pageID: UUID?
    /// Page points per screen point at the last touch, so the dot looks the same size at any zoom.
    private(set) var pageUnitsPerPoint: CGFloat = 1
    private(set) var isAnimating = false
    private(set) var colorID: String
    private(set) var diameter: Double
    private(set) var style: LaserTrailModel.Style

    @ObservationIgnored private var fadeTask: Task<Void, Never>?

    private enum Keys {
        static let color = "present.laser.color", diameter = "present.laser.diameter", style = "present.laser.style"
    }

    init() {
        let defaults = UserDefaults.standard
        colorID = defaults.string(forKey: Keys.color) ?? LaserColor.all[0].id
        let stored = defaults.double(forKey: Keys.diameter)
        diameter = stored > 0 ? stored : 16
        style = defaults.string(forKey: Keys.style).flatMap(LaserTrailModel.Style.init(rawValue:)) ?? .trail
        model.style = style
    }

    var color: Color { LaserColor.color(for: colorID) }

    func setColor(_ id: String) {
        colorID = id
        Self.save(id, key: Keys.color)
    }

    func setDiameter(_ value: Double) {
        diameter = value
        Self.save(value, key: Keys.diameter)
    }

    func setStyle(_ value: LaserTrailModel.Style) {
        style = value
        model.style = value
        Self.save(value.rawValue, key: Keys.style)
    }

    static func now() -> TimeInterval { ProcessInfo.processInfo.systemUptime }

    func touchMoved(on pageID: UUID, at location: CGPoint, zoomScale: CGFloat) {
        fadeTask?.cancel()
        isAnimating = true
        pageUnitsPerPoint = 1 / max(zoomScale, 0.05)
        if self.pageID != pageID {
            model.clear()
            self.pageID = pageID
        }
        model.move(to: location, time: Self.now())
    }

    func touchEnded() {
        model.end(time: Self.now())
        let wait = model.fadeDuration + 0.1
        fadeTask?.cancel()
        fadeTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(wait)) } catch { return }
            self?.finishFade()
        }
    }

    func reset() {
        fadeTask?.cancel()
        model.clear()
        isAnimating = false
    }

    private func finishFade() {
        model.prune(now: Self.now())
        if model.isFadedOut(at: Self.now()) {
            model.clear()
            isAnimating = false
        }
    }

    private static func save(_ value: Any, key: String) { UserDefaults.standard.set(value, forKey: key) }
}

struct LaserColor: Identifiable, Equatable {
    let id: String
    let name: LocalizedStringResource
    let color: Color

    static let all: [LaserColor] = [
        LaserColor(id: "red", name: LocalizedStringResource("Red", table: "Present"), color: Color(red: 1, green: 0.16, blue: 0.2)),
        LaserColor(id: "green", name: LocalizedStringResource("Green", table: "Present"), color: Color(red: 0.1, green: 0.85, blue: 0.3)),
        LaserColor(id: "blue", name: LocalizedStringResource("Blue", table: "Present"), color: Color(red: 0.2, green: 0.5, blue: 1)),
        LaserColor(id: "orange", name: LocalizedStringResource("Orange", table: "Present"), color: Color(red: 1, green: 0.6, blue: 0.1)),
        LaserColor(id: "violet", name: LocalizedStringResource("Violet", table: "Present"), color: Color(red: 0.7, green: 0.35, blue: 1)),
    ]

    static func color(for id: String) -> Color { all.first { $0.id == id }?.color ?? all[0].color }
}
