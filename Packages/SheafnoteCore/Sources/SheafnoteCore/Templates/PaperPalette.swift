import CoreGraphics
import Foundation

public struct RGBAColor: Codable, Hashable, Sendable {
    public var r: Double, g: Double, b: Double, a: Double

    public init(r: Double, g: Double, b: Double, a: Double = 1) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    /// "#RRGGBB", "RRGGBB" or "#RRGGBBAA". Returns nil for anything else.
    public init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6 || s.count == 8, let v = UInt64(s, radix: 16) else { return nil }
        let hasAlpha = s.count == 8
        let shift: UInt64 = hasAlpha ? 8 : 0
        r = Double((v >> (16 + shift)) & 0xFF) / 255
        g = Double((v >> (8 + shift)) & 0xFF) / 255
        b = Double((v >> shift) & 0xFF) / 255
        a = hasAlpha ? Double(v & 0xFF) / 255 : 1
    }

    public var cgColor: CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }

    public func withAlpha(_ alpha: Double) -> RGBAColor { RGBAColor(r: r, g: g, b: b, a: alpha) }
}

/// Paper and ink-on-paper colors for each paper color.
public struct PaperPalette: Sendable, Hashable {
    public var paper: RGBAColor
    public var minor: RGBAColor
    public var major: RGBAColor
    public var accent: RGBAColor
    public var text: RGBAColor

    public static func palette(for color: PaperColor) -> PaperPalette {
        switch color {
        case .white:
            PaperPalette(paper: .init(hex: "FFFFFF")!, minor: .init(hex: "C6D0E0")!, major: .init(hex: "8FA1BD")!,
                         accent: .init(hex: "E08A8A")!, text: .init(hex: "7B879C")!)
        case .yellow:
            PaperPalette(paper: .init(hex: "FBF1C4")!, minor: .init(hex: "D9CC96")!, major: .init(hex: "B3A56A")!,
                         accent: .init(hex: "D98A7A")!, text: .init(hex: "8F8458")!)
        case .dark:
            PaperPalette(paper: .init(hex: "1F2023")!, minor: .init(hex: "3A3D44")!, major: .init(hex: "5C616C")!,
                         accent: .init(hex: "8E5A5F")!, text: .init(hex: "8A909B")!)
        }
    }

    func color(for role: LineRole) -> RGBAColor {
        switch role {
        case .minor: minor
        case .major: major
        case .accent: accent
        }
    }
}
