import Foundation
import SheafnoteCore

/// The paper a new notebook starts with. Synced setting "defaults.paper"; also remembers the last choice.
struct PaperDefaults: Codable, Equatable {
    var template: TemplateSpec
    var color: PaperColor
    var size: PaperSize
    var orientation: PageOrientation
    var coverID: String

    static let fallback = PaperDefaults(template: TemplateSpec(kind: .ruledCollege), color: .white, size: .a4,
                                        orientation: .portrait, coverID: CoverSpec.default.coverID)
}

extension AppSettingsStore {
    var paperDefaults: PaperDefaults {
        synced("defaults.paper", as: PaperDefaults.self) ?? .fallback
    }

    func savePaperDefaults(_ value: PaperDefaults) throws {
        try setSynced(value, for: "defaults.paper")
    }

    var units: MeasurementUnits {
        get { local("units", as: MeasurementUnits.self) ?? .automatic }
        set { setLocal(newValue, for: "units") }
    }
}
