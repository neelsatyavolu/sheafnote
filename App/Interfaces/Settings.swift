import SwiftUI

struct SettingsSection: Identifiable {
    let id: String
    let order: Int
    let title: LocalizedStringResource
    let symbolName: String
    /// Form content (Sections and rows). Foundation wraps it in a `Form` and pushes it from the Settings list.
    let makeView: @MainActor (AppServices) -> AnyView
}

/// Order values: General 0, Pencil & gestures 10, iCloud sync 20, Import & backup 30, Search 40, App lock 50, Audio 60, About 100.
@MainActor
final class SettingsRegistry {
    private var storage: [SettingsSection] = []

    func register(_ section: SettingsSection) {
        storage.removeAll { $0.id == section.id }
        storage.append(section)
    }

    var sections: [SettingsSection] { storage.sorted { $0.order < $1.order } }
}
