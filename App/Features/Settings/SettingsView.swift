import SwiftUI

/// Lists the sections that features registered. Each section's content is shown inside a pushed Form.
struct SettingsView: View {
    @Environment(FeatureHost.self) private var host
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(host.settings.sections) { section in
                NavigationLink {
                    Form { section.makeView(host.services) }
                        .navigationTitle(Text(section.title))
                        .navigationBarTitleDisplayMode(.inline)
                } label: {
                    Label { Text(section.title) } icon: { Image(systemName: section.symbolName) }
                }
                .accessibilityIdentifier("settings.\(section.id)")
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.accessibilityIdentifier("settings.done") }
            }
        }
        .presentationDetents([.large])
    }
}
