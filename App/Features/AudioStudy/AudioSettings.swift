import SwiftUI
import SheafnoteCore

/// "Audio" section in Settings (order 60): default recording quality.
enum AudioSettings {
    @MainActor static func quality(_ settings: AppSettingsStore) -> RecordingQuality {
        settings.synced(RecordingQuality.settingsKey, as: String.self).flatMap(RecordingQuality.init(rawValue:)) ?? .standard
    }

    @MainActor
    static var section: SettingsSection {
        SettingsSection(id: "audio", order: 60, title: LocalizedStringResource("Audio", table: "AudioStudy"),
                        symbolName: "waveform") { services in
            AnyView(AudioSettingsContent(settings: services.settings))
        }
    }
}

private struct AudioSettingsContent: View {
    let settings: AppSettingsStore
    @State private var quality: RecordingQuality
    @State private var saveError: String?

    init(settings: AppSettingsStore) {
        self.settings = settings
        _quality = State(initialValue: AudioSettings.quality(settings))
    }

    var body: some View {
        Section {
            Picker(selection: $quality) {
                Text("Standard", tableName: "AudioStudy").tag(RecordingQuality.standard)
                Text("High", tableName: "AudioStudy").tag(RecordingQuality.high)
            } label: {
                Text("Recording quality", tableName: "AudioStudy")
            }
            .accessibilityIdentifier("audio.settings.quality")
            .onChange(of: quality) { _, new in
                do {
                    try settings.setSynced(new.rawValue, for: RecordingQuality.settingsKey)
                    saveError = nil
                } catch {
                    saveError = error.localizedDescription
                }
            }
            if let saveError { Text(saveError).foregroundStyle(.red).font(.footnote) }
        } header: {
            Text("Audio", tableName: "AudioStudy")
        } footer: {
            Text("Standard is smaller and clear for speech. High keeps more detail for music. Applies to new recordings.",
                 tableName: "AudioStudy")
        }
    }
}
