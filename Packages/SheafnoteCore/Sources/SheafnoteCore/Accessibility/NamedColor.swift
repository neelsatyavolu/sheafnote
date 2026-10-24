import Foundation

/// Plain-language color names for VoiceOver ("Blue" instead of "#1A73E8"). The app localizes the cases.
public enum NamedColor: String, CaseIterable, Sendable {
    case black, white, gray, red, orange, yellow, green, teal, blue, purple, pink, brown

    /// The closest named color for a `#RRGGBB` (or `#RRGGBBAA`) string; nil when the string is not a hex color.
    public static func nearest(toHex hex: String) -> NamedColor? {
        var digits = hex.trimmingCharacters(in: .whitespaces)
        if digits.hasPrefix("#") { digits.removeFirst() }
        guard digits.count == 6 || digits.count == 8, let value = UInt64(digits.prefix(6), radix: 16) else { return nil }
        let r = Double((value >> 16) & 0xFF) / 255, g = Double((value >> 8) & 0xFF) / 255, b = Double(value & 0xFF) / 255
        let high = max(r, g, b), low = min(r, g, b), delta = high - low
        let saturation = high == 0 ? 0 : delta / high
        if high < 0.2 { return .black }
        if saturation < 0.12 { return high > 0.88 ? .white : .gray }
        let hue = Self.hue(r, g, b, high: high, delta: delta)
        if hue >= 15, hue < 45, high < 0.62, saturation > 0.35 { return .brown }
        switch hue {
        case ..<15, 345...: return .red
        case ..<40: return .orange
        case ..<70: return .yellow
        case ..<165: return .green
        case ..<200: return .teal
        case ..<255: return .blue
        case ..<300: return .purple
        default: return .pink
        }
    }

    private static func hue(_ r: Double, _ g: Double, _ b: Double, high: Double, delta: Double) -> Double {
        guard delta > 0 else { return 0 }
        let raw: Double
        if high == r { raw = ((g - b) / delta).truncatingRemainder(dividingBy: 6) }
        else if high == g { raw = (b - r) / delta + 2 }
        else { raw = (r - g) / delta + 4 }
        let degrees = raw * 60
        return degrees < 0 ? degrees + 360 : degrees
    }
}
