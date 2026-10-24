import SwiftUI

/// Covers tilt toward the viewer and lift slightly while pressed. With Reduce Motion they only dim slightly.
struct CoverPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PressBody(configuration: configuration)
    }

    private struct PressBody: View {
        let configuration: Configuration
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            let pressed = configuration.isPressed
            configuration.label
                .opacity(pressed && reduceMotion ? 0.8 : 1)
                .scaleEffect(pressed && !reduceMotion ? 1.04 : 1)
                .rotation3DEffect(.degrees(pressed && !reduceMotion ? -7 : 0), axis: (x: 0, y: 1, z: 0),
                                  anchor: .leading, perspective: 0.5)
                .offset(y: pressed && !reduceMotion ? -3 : 0)
                .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.6), value: pressed)
        }
    }
}
