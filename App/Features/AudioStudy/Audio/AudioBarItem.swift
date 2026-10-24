import SwiftUI
import SheafnoteCore

/// Top-bar button (trailing) that opens the Audio sheet and shows the recording clock while recording.
struct AudioBarButton: View {
    let editor: any EditorContext

    var body: some View {
        let session = AudioStudyHub.shared.session(for: editor)
        Button {
            AudioStudyFeature.presentAudioSheet(in: editor)
        } label: {
            if session.recorder.isRecording {
                Label { Text(AudioTimeFormat.clock(session.recorder.elapsed)) } icon: {
                    Image(systemName: "record.circle.fill").foregroundStyle(.red)
                }
                .font(.subheadline.monospacedDigit())
            } else {
                Image(systemName: session.player.isLoaded ? "waveform.circle.fill" : "waveform.circle")
            }
        }
        .accessibilityLabel(session.recorder.isRecording
                            ? Text("Audio, recording", tableName: "AudioStudy") : Text("Audio", tableName: "AudioStudy"))
        .accessibilityIdentifier("audio.bar")
    }
}
