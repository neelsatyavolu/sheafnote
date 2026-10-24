import CoreGraphics
import Foundation

public struct TapeSwatch: Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var hex: String
    public var style: TapeStyle
}

/// Pure logic for study tape: which state a tape is in, toggling it, and turning a drag into a tape rectangle.
public enum StudyTape {
    /// A tape shorter or thinner than this is considered an accidental tap and is not created.
    public static let minimumLength: CGFloat = 24
    public static let minimumThickness: CGFloat = 16

    public static let swatches: [TapeSwatch] = [
        TapeSwatch(id: "coral", name: "Coral", hex: "#F08A6C", style: .solid),
        TapeSwatch(id: "amber", name: "Amber", hex: "#F2C14E", style: .solid),
        TapeSwatch(id: "mint", name: "Mint", hex: "#6CCBA4", style: .solid),
        TapeSwatch(id: "sky", name: "Sky", hex: "#6BB1E8", style: .solid),
        TapeSwatch(id: "violet", name: "Violet", hex: "#A88BE0", style: .solid),
        TapeSwatch(id: "slate", name: "Slate", hex: "#4A5668", style: .solid),
        TapeSwatch(id: "striped-rose", name: "Rose Stripes", hex: "#EE7C9A", style: .striped),
        TapeSwatch(id: "washi-teal", name: "Teal Washi", hex: "#5FB7B0", style: .washi),
    ]

    public static func toggled(_ payload: TapePayload) -> TapePayload {
        var copy = payload
        copy.isRevealed.toggle()
        return copy
    }

    /// Whether the tape hides what is under it. `forceHide` is the export/render switch `RenderOptions.hideTape`.
    public static func isCovering(_ payload: TapePayload, forceHide: Bool) -> Bool {
        forceHide || !payload.isRevealed
    }

    /// The tape elements among `elements` whose state differs from `revealed`, already updated. Other kinds and
    /// undecodable payloads are skipped (never altered).
    public static func settingRevealed(_ revealed: Bool, in elements: [ElementValue]) -> [ElementValue] {
        elements.compactMap { element in
            guard element.kind == .tape,
                  var payload = PayloadCodec.decode(TapePayload.self, from: element.payload),
                  payload.isRevealed != revealed else { return nil }
            payload.isRevealed = revealed
            var copy = element
            copy.payload = PayloadCodec.encode(payload)
            return copy
        }
    }

    /// True when every tape in `elements` is currently covering (so the next toggle-all should reveal).
    public static func allCovering(in elements: [ElementValue]) -> Bool {
        let payloads = elements.filter { $0.kind == .tape }.compactMap { PayloadCodec.decode(TapePayload.self, from: $0.payload) }
        return !payloads.isEmpty && payloads.allSatisfy { !$0.isRevealed }
    }

    /// The rectangle a drag from `start` to `end` lays down, clamped to the page. Returns nil for a tap.
    public static func rect(from start: CGPoint, to end: CGPoint, pageSize: CGSize) -> CGRect? {
        var rect = CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                          width: abs(end.x - start.x), height: abs(end.y - start.y))
        guard max(rect.width, rect.height) >= minimumLength else { return nil }
        if rect.height < minimumThickness {
            rect = CGRect(x: rect.minX, y: rect.midY - minimumThickness / 2, width: rect.width, height: minimumThickness)
        }
        if rect.width < minimumThickness {
            rect = CGRect(x: rect.midX - minimumThickness / 2, y: rect.minY, width: minimumThickness, height: rect.height)
        }
        let bounds = CGRect(origin: .zero, size: pageSize)
        guard !bounds.isEmpty else { return rect }
        return rect.intersection(bounds).isNull ? nil : rect.intersection(bounds)
    }

    public static func element(pageID: UUID, rect: CGRect, swatch: TapeSwatch, zIndex: Int) -> ElementValue {
        ElementValue(pageID: pageID, kind: .tape, frame: rect, zIndex: zIndex,
                     payload: PayloadCodec.encode(TapePayload(colorHex: swatch.hex, isRevealed: false, style: swatch.style)))
    }
}
