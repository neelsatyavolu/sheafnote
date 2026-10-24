import SwiftUI
import SheafnoteCore

enum GeneralSettings {
    static let section = SettingsSection(id: "general", order: 0, title: "General", symbolName: "gearshape") { services in
        AnyView(GeneralSettingsContent(services: services))
    }
}

private struct GeneralSettingsContent: View {
    let services: AppServices
    @State private var defaults: PaperDefaults
    @State private var units: MeasurementUnits
    @State private var saveError: String?

    init(services: AppServices) {
        self.services = services
        _defaults = State(initialValue: services.settings.paperDefaults)
        _units = State(initialValue: services.settings.units)
    }

    var body: some View {
        Section("Default Paper") {
            TemplatePickerView(template: $defaults.template, paperColor: $defaults.color,
                               pageSize: defaults.size.size(orientation: defaults.orientation))
            Picker("Size", selection: $defaults.size) {
                ForEach(PaperSize.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Picker("Orientation", selection: $defaults.orientation) {
                ForEach(PageOrientation.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .disabled(!defaults.size.supportsOrientation)
        }
        Section {
            Picker("Units", selection: $units) {
                ForEach(MeasurementUnits.allCases, id: \.self) { Text($0.title).tag($0) }
            }
        } footer: {
            Text("Used for paper sizes, such as 210 × 297 mm or 8.3 × 11.7 in.")
        }
        .onChange(of: defaults) { _, new in
            do { try services.settings.savePaperDefaults(new) } catch { saveError = error.localizedDescription }
        }
        .onChange(of: units) { _, new in services.settings.units = new }
        .alert("Couldn't Save Settings", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(saveError ?? "") }
    }
}

enum AboutSettings {
    static let section = SettingsSection(id: "about", order: 100, title: "About", symbolName: "info.circle") { _ in
        AnyView(AboutContent())
    }
}

private struct AboutContent: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    var body: some View {
        Section {
            LabeledContent("Version", value: version)
            LabeledContent("License", value: "MIT")
        }
        Section {
            Label("No tracking. No analytics. No accounts.", systemImage: "hand.raised")
            Label("Your notes stay on your devices and in your own iCloud.", systemImage: "icloud")
        } header: {
            Text("Privacy")
        } footer: {
            Text("Sheafnote is free and open source software. It only talks to the network to sync with your iCloud, and only when you leave sync on.")
        }
    }
}
