import SwiftUI

enum AudioTimeFormat {
    /// "3:07" or "1:02:09".
    static func clock(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

/// Play/pause, skip, scrubber and speed for the loaded recording.
struct PlayerBar: View {
    let session: AudioStudySession
    var showsClose = true

    private var player: PlaybackController { session.player }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 14) {
                Button { player.skip(by: -10) } label: { Image(systemName: "gobackward.10") }
                    .accessibilityLabel(Text("Back 10 seconds", tableName: "AudioStudy"))
                    .accessibilityIdentifier("audio.player.back")
                Button { player.togglePlay() } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.title2).frame(width: 34)
                }
                .accessibilityLabel(player.isPlaying ? Text("Pause", tableName: "AudioStudy") : Text("Play", tableName: "AudioStudy"))
                .accessibilityIdentifier("audio.player.playPause")
                Button { player.skip(by: 10) } label: { Image(systemName: "goforward.10") }
                    .accessibilityLabel(Text("Forward 10 seconds", tableName: "AudioStudy"))
                    .accessibilityIdentifier("audio.player.forward")
                Spacer(minLength: 8)
                speedMenu
                if showsClose {
                    Button { session.endPlayback() } label: { Image(systemName: "xmark.circle.fill") }
                        .accessibilityLabel(Text("Close player", tableName: "AudioStudy"))
                        .accessibilityIdentifier("audio.player.close")
                }
            }
            .buttonStyle(.borderless)
            scrubber
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var scrubber: some View {
        HStack(spacing: 8) {
            Text(AudioTimeFormat.clock(player.currentTime)).font(.caption.monospacedDigit())
            Slider(value: Binding(get: { player.currentTime }, set: { player.seek(to: $0) }),
                   in: 0...max(player.duration, 0.1))
                .accessibilityLabel(Text("Playback position", tableName: "AudioStudy"))
                .accessibilityValue(Text("\(AudioTimeFormat.clock(player.currentTime)) of \(AudioTimeFormat.clock(player.duration))",
                                         tableName: "AudioStudy"))
                .accessibilityIdentifier("audio.player.scrubber")
            Text(AudioTimeFormat.clock(player.duration)).font(.caption.monospacedDigit())
        }
        .foregroundStyle(Theme.inkMuted)
    }

    private var speedMenu: some View {
        @Bindable var player = player
        return Menu {
            Picker(selection: $player.rate) {
                ForEach([Float(0.75), 1, 1.25, 1.5, 2], id: \.self) { Text(verbatim: "\($0.formatted())x").tag($0) }
            } label: { Text("Speed", tableName: "AudioStudy") }
        } label: {
            Text(verbatim: "\(player.rate.formatted())x").font(.subheadline.monospacedDigit())
        }
        .accessibilityLabel(Text("Playback speed", tableName: "AudioStudy"))
        .accessibilityIdentifier("audio.player.speed")
    }
}
