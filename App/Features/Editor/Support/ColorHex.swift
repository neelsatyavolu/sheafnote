import SwiftUI
import UIKit
import SheafnoteCore

/// "#RRGGBB" conversions for ink colors. Colors are stored as hex so presets sync as plain JSON.
extension UIColor {
    convenience init(hex: String) {
        let c = RGBAColor(hex: hex) ?? RGBAColor(r: 0, g: 0, b: 0)
        self.init(red: c.r, green: c.g, blue: c.b, alpha: c.a)
    }

    /// Uppercase "#RRGGBB" in sRGB, alpha dropped.
    var hexString: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        let light = resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        if light.getRed(&r, green: &g, blue: &b, alpha: &a) { return Self.format(r, g, b) }
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let comps = light.cgColor.converted(to: space, intent: .defaultIntent, options: nil)?.components,
              comps.count >= 3 else { return "#000000" }
        return Self.format(comps[0], comps[1], comps[2])
    }

    private static func format(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> String {
        func byte(_ v: CGFloat) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(r), byte(g), byte(b))
    }
}

extension Color {
    init(hex: String) { self.init(uiColor: UIColor(hex: hex)) }

    var hexString: String { UIColor(self).hexString }
}
