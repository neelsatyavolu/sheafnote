import SwiftUI
import UIKit

/// Shared look of the editor chrome: option-row chips, preset rings, width strokes and tool tinting. Tokens only.
extension View {
    /// The 10pt paperRaised chip behind every options row.
    func optionsCapsule() -> some View {
        background(Theme.paperRaised, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous).strokeBorder(Theme.rule, lineWidth: 1))
    }
}

struct OptionsDivider: View {
    var body: some View {
        Rectangle().fill(Theme.rule).frame(width: 1, height: 22).accessibilityHidden(true)
    }
}

/// Tap-target size of option-row controls: 44pt on iPad, 38pt on iPhone so a full pen row fits the screen width.
struct OptionsMetrics {
    let target: CGFloat
    let spacing: CGFloat

    init(compact: Bool) {
        target = compact ? 38 : 44
        spacing = compact ? 2 : 6
    }
}

/// A color dot for presets and palettes: a hairline outline, and a clean ink ring when selected.
struct PresetDot: View {
    let color: Color
    let selected: Bool
    var diameter: CGFloat = 26

    var body: some View {
        Circle().fill(color)
            .frame(width: diameter, height: diameter)
            .overlay(Circle().strokeBorder(Theme.ink.opacity(0.18), lineWidth: 1))
            .overlay {
                if selected { Circle().strokeBorder(Theme.ink, lineWidth: 2).padding(-4) }
            }
    }
}

/// A width preset drawn as a short ink stroke of that width.
struct WidthStroke: View {
    let width: Double
    let tint: Color

    /// Saturating curve so thin, medium and thick stay distinct from 1.5pt pens to 48pt erasers.
    static func height(for width: Double) -> CGFloat { 2 + 12 * (1 - exp(-CGFloat(width) / 12)) }

    var body: some View {
        Capsule().fill(tint).frame(width: 24, height: Self.height(for: width))
    }
}

extension UIColor {
    /// Perceived brightness in 0...1.
    var luminance: CGFloat {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return 0.299 * r + 0.587 * g + 0.114 * b
    }
}

extension Color {
    /// This ink color, or `Theme.ink` when it would vanish against the current paper (dark ink at night, white ink by day).
    func legible(on scheme: ColorScheme) -> Color {
        let style: UIUserInterfaceStyle = scheme == .dark ? .dark : .light
        let lum = UIColor(self).resolvedColor(with: UITraitCollection(userInterfaceStyle: style)).luminance
        if scheme == .dark, lum < 0.3 { return Theme.ink }
        if scheme == .light, lum > 0.88 { return Theme.ink }
        return self
    }
}

extension Theme {
    /// The area around the pages: a little deeper than paper so white, yellow and dark pages all stand out.
    static func backdrop(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Theme.paper.mix(with: .black, by: 0.4) : Theme.paper.mix(with: Theme.ink, by: 0.07)
    }

    /// Warm page shadow color, the same in both appearances (ink in its light-mode brown).
    static var pageShadowUIColor: UIColor {
        (UIColor(named: "Ink") ?? .black).resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
    }
}
