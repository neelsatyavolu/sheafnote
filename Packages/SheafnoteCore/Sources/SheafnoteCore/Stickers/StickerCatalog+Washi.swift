import CoreGraphics
import Foundation

extension StickerCatalog {
    private static let strip = CGSize(width: 200, height: 40)
    private static let base = CGRect(x: 0, y: 2, width: 200, height: 36)

    /// The torn-edge base shape every washi strip starts with (pattern layers clip to it).
    private static func baseLayer() -> StickerLayer {
        StickerLayer(P.tornStrip(base, teeth: 6, depth: 4), fill: .primary, opacity: 0.9)
    }

    private static func washiStrip(_ id: String, _ name: String, primary: String, pattern: [StickerLayer]) -> StickerDefinition {
        make(id, name, .washi, size: strip, primary: primary, secondary: primary, [baseLayer()] + pattern)
    }

    static let washi: [StickerDefinition] = [
        washiStrip("washi-plain", "Plain Washi", primary: "#FF6FA8", pattern: [
            StickerLayer(P.rect(CGRect(x: 0, y: 8, width: 200, height: 6)), fill: .white, opacity: 0.28, clipToBase: true),
        ]),
        washiStrip("washi-stripes", "Striped Washi", primary: "#3D9BFF", pattern: stripeLayers()),
        washiStrip("washi-dots", "Dotted Washi", primary: "#3CC9A0", pattern: dotLayers()),
        washiStrip("washi-checks", "Checked Washi", primary: "#A77BFF", pattern: checkLayers()),
        washiStrip("washi-wave", "Wavy Washi", primary: "#FFC93C", pattern: [
            line(waveCommands(amplitude: 8), paint: .white, width: 3, opacity: 0.85, clip: true),
        ]),
        washiStrip("washi-zigzag", "Zigzag Washi", primary: "#F2542D", pattern: [
            line(P.polyline(zigzagPoints()), paint: .white, width: 3, opacity: 0.85, clip: true),
        ]),
        washiStrip("washi-grid", "Grid Washi", primary: "#FFC93C", pattern: gridLayers()),
        washiStrip("washi-stars", "Starry Washi", primary: "#3CC9A0", pattern: starLayers()),
    ]

    private static func stripeLayers() -> [StickerLayer] {
        stride(from: CGFloat(-10), to: 220, by: 26).map { x in
            StickerLayer(P.polygon([pt(x, 0), pt(x + 11, 0), pt(x - 7, 40), pt(x - 18, 40)]),
                         fill: .white, opacity: 0.55, clipToBase: true)
        }
    }

    private static func dotLayers() -> [StickerLayer] {
        var layers: [StickerLayer] = []
        for (row, y) in [CGFloat(12), 28].enumerated() {
            let offset: CGFloat = row == 0 ? 0 : 9
            for x in stride(from: CGFloat(9) + offset, to: 200, by: 18) {
                layers.append(dot(x, y, radius: 3.5, opacity: 0.8, clip: true))
            }
        }
        return layers
    }

    private static func checkLayers() -> [StickerLayer] {
        var layers: [StickerLayer] = []
        for row in 0..<3 {
            for col in 0..<17 where (row + col).isMultiple(of: 2) {
                let rect = CGRect(x: CGFloat(col) * 12, y: 2 + CGFloat(row) * 12, width: 12, height: 12)
                layers.append(StickerLayer(P.rect(rect), fill: .white, opacity: 0.45, clipToBase: true))
            }
        }
        return layers
    }

    private static func gridLayers() -> [StickerLayer] {
        let vertical = stride(from: CGFloat(10), to: 200, by: 14).map { x in
            line(P.polyline([pt(x, 0), pt(x, 40)]), paint: .white, width: 1.2, opacity: 0.7, clip: true)
        }
        let horizontal = [CGFloat(14), 26].map { y in
            line(P.polyline([pt(0, y), pt(200, y)]), paint: .white, width: 1.2, opacity: 0.7, clip: true)
        }
        return vertical + horizontal
    }

    private static func starLayers() -> [StickerLayer] {
        var layers: [StickerLayer] = []
        for (row, y) in [CGFloat(13), 27].enumerated() {
            let offset: CGFloat = row == 0 ? 0 : 12
            for x in stride(from: CGFloat(12) + offset, to: 200, by: 24) {
                layers.append(StickerLayer(P.star(center: pt(x, y), outer: 6, inner: 2.6, points: 5),
                                           fill: .white, opacity: 0.8, clipToBase: true))
            }
        }
        return layers
    }

    private static func waveCommands(amplitude: CGFloat) -> [StickerCommand] {
        var commands: [StickerCommand] = [.move(pt(0, 20))]
        for i in 0..<10 {
            let x = CGFloat(i) * 20
            let bend: CGFloat = i.isMultiple(of: 2) ? -amplitude : amplitude
            commands.append(.quad(to: pt(x + 20, 20), control: pt(x + 10, 20 + bend * 2)))
        }
        return commands
    }

    private static func zigzagPoints() -> [CGPoint] {
        stride(from: CGFloat(0), through: 200, by: 12).enumerated().map { i, x in pt(x, i.isMultiple(of: 2) ? 28 : 12) }
    }
}
