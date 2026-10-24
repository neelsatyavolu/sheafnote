import SwiftUI
import SheafnoteCore

/// The "Audio" sheet: record, list, rename, delete and play recordings of one notebook.
struct AudioSheet: View {
    let session: AudioStudySession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var renaming: AudioRecording?
    @State private var newTitle = ""
    @State private var deleting: AudioRecording?

    private var recorder: RecorderController { session.recorder }

    var body: some View {
        NavigationStack {
            List {
                Section { recordControls }
                if let message = session.errorMessage { Section { problem(message) } }
                Section {
                    if session.items.isEmpty {
                        Text("No recordings yet. Start one, then write: tap a stroke later to hear what was said.",
                             tableName: "AudioStudy")
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("audio.empty")
                    }
                    ForEach(session.items) { row($0) }
                } header: {
                    Text("Recordings", tableName: "AudioStudy")
                }
            }
            .navigationTitle(Text("Audio", tableName: "AudioStudy"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Text("Done", tableName: "AudioStudy") }
                        .accessibilityIdentifier("audio.done")
                }
            }
            .safeAreaInset(edge: .bottom) {
                if session.player.isLoaded { PlayerBar(session: session).background(.bar) }
            }
        }
        .alert(Text("Rename recording", tableName: "AudioStudy"), isPresented: Binding(
            get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField(text: $newTitle) { Text("Title", tableName: "AudioStudy") }
            Button { if let r = renaming { session.rename(r, to: newTitle) } } label: { Text("Rename", tableName: "AudioStudy") }
            Button(role: .cancel) {} label: { Text("Cancel", tableName: "AudioStudy") }
        }
        .confirmationDialog(Text("Delete this recording?", tableName: "AudioStudy"), isPresented: Binding(
            get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button(role: .destructive) { if let r = deleting { session.delete(r) } } label: { Text("Delete", tableName: "AudioStudy") }
        } message: {
            Text("The notebook's writing is not affected.", tableName: "AudioStudy")
        }
        .task { session.reload() }
    }

    // MARK: Recording

    @ViewBuilder
    private var recordControls: some View {
        Button {
            Task { await session.toggleRecording() }
        } label: {
            HStack {
                Image(systemName: recorder.isRecording ? "stop.circle.fill" : "record.circle")
                    .font(.title).foregroundStyle(.red)
                VStack(alignment: .leading) {
                    recorder.isRecording ? Text("Stop recording", tableName: "AudioStudy") : Text("Start recording", tableName: "AudioStudy")
                    if recorder.isRecording {
                        Text(AudioTimeFormat.clock(recorder.elapsed)).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
        }
        .disabled(recorder.isBusy)
        .accessibilityIdentifier("audio.record")
        .accessibilityValue(recorder.isRecording ? Text(AudioTimeFormat.clock(recorder.elapsed)) : Text(verbatim: ""))
        if recorder.state == .denied { deniedBanner }
        if case .failed(let message) = recorder.state { problem(message, dismiss: recorder.dismissProblem) }
        if let notice = recorder.notice { Text(notice).font(.footnote).foregroundStyle(.secondary) }
    }

    private var deniedBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label { Text("Microphone access is off", tableName: "AudioStudy") } icon: { Image(systemName: "mic.slash") }
                .font(.headline)
            Text("Sheafnote needs the microphone to record. Turn it on in Settings, then come back.", tableName: "AudioStudy")
                .font(.subheadline)
            if let url = URL(string: UIApplication.openSettingsURLString) {
                Button { openURL(url) } label: { Text("Open Settings", tableName: "AudioStudy") }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("audio.openSettings")
            }
        }
        .accessibilityIdentifier("audio.denied")
    }

    private func problem(_ message: String, dismiss: (() -> Void)? = nil) -> some View {
        HStack(alignment: .top) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(message).font(.subheadline)
            Spacer()
            Button { (dismiss ?? session.dismissError)() } label: { Image(systemName: "xmark") }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("Dismiss", tableName: "AudioStudy"))
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("audio.problem")
    }

    // MARK: List

    private func row(_ recording: AudioRecording) -> some View {
        Button { session.beginPlayback(recording); dismissIfWriting() } label: {
            HStack {
                Image(systemName: session.player.recording?.id == recording.id ? "speaker.wave.2.fill" : "play.circle")
                    .foregroundStyle(.tint)
                VStack(alignment: .leading) {
                    Text(recording.title).foregroundStyle(.primary)
                    Text("\(recording.startedAt, format: .dateTime.day().month().hour().minute()) · \(AudioTimeFormat.clock(recording.duration))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .swipeActions {
            Button(role: .destructive) { deleting = recording } label: { Label { Text("Delete", tableName: "AudioStudy") } icon: { Image(systemName: "trash") } }
            Button { newTitle = recording.title; renaming = recording } label: { Label { Text("Rename", tableName: "AudioStudy") } icon: { Image(systemName: "pencil") } }
                .tint(.blue)
        }
        .contextMenu {
            Button { newTitle = recording.title; renaming = recording } label: { Label { Text("Rename", tableName: "AudioStudy") } icon: { Image(systemName: "pencil") } }
            Button(role: .destructive) { deleting = recording } label: { Label { Text("Delete", tableName: "AudioStudy") } icon: { Image(systemName: "trash") } }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Plays the recording. Tap a stroke on the page to jump to when it was written.", tableName: "AudioStudy"))
        .accessibilityIdentifier("audio.row.\(recording.title)")
    }

    /// Starting playback from a compact sheet: get out of the way so the page can be tapped.
    private func dismissIfWriting() { if session.player.isLoaded { dismiss() } }
}
