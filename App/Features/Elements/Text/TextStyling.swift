import UIKit
import SheafnoteCore

struct FontChoice: Identifiable, Hashable {
    let id: String          // stored in TextPayload.fontName
    let displayName: String
}

/// Turns a `TextPayload` into fonts and attributed strings. The live view, the editor and the export path all use
/// this, so what you type is what you see and what you export.
enum TextStyling {
    static let systemName = "System"

    static let fontChoices: [FontChoice] = [
        FontChoice(id: systemName, displayName: "System"),
        FontChoice(id: "System Serif", displayName: "Serif"),
        FontChoice(id: "System Rounded", displayName: "Rounded"),
        FontChoice(id: "System Monospaced", displayName: "Monospaced"),
        FontChoice(id: "Georgia", displayName: "Georgia"),
        FontChoice(id: "Palatino", displayName: "Palatino"),
        FontChoice(id: "Avenir Next", displayName: "Avenir Next"),
        FontChoice(id: "Helvetica Neue", displayName: "Helvetica Neue"),
        FontChoice(id: "Noteworthy", displayName: "Noteworthy"),
        FontChoice(id: "Marker Felt", displayName: "Marker Felt"),
        FontChoice(id: "American Typewriter", displayName: "American Typewriter"),
    ]

    static let sizes: [Double] = [10, 12, 14, 16, 18, 20, 24, 28, 32, 40, 48, 64]

    static func font(for payload: TextPayload) -> UIFont {
        let size = CGFloat(min(max(payload.fontSize, 6), 400))
        let base = baseFont(named: payload.fontName, size: size)
        var traits: UIFontDescriptor.SymbolicTraits = []
        if payload.isBold { traits.insert(.traitBold) }
        if payload.isItalic { traits.insert(.traitItalic) }
        guard !traits.isEmpty else { return base }
        let merged = base.fontDescriptor.symbolicTraits.union(traits)
        if let descriptor = base.fontDescriptor.withSymbolicTraits(merged) { return UIFont(descriptor: descriptor, size: size) }
        return base
    }

    private static func baseFont(named name: String, size: CGFloat) -> UIFont {
        let system = UIFont.systemFont(ofSize: size)
        let design: UIFontDescriptor.SystemDesign? = switch name {
        case "System Serif": .serif
        case "System Rounded": .rounded
        case "System Monospaced": .monospaced
        default: nil
        }
        if let design, let descriptor = system.fontDescriptor.withDesign(design) { return UIFont(descriptor: descriptor, size: size) }
        if name == systemName || design != nil { return system }
        return UIFont(name: name, size: size) ?? system
    }

    static func paragraphStyle(for payload: TextPayload) -> NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.alignment = switch payload.alignment {
        case .leading: .natural
        case .center: .center
        case .trailing: .right
        }
        style.lineBreakMode = .byWordWrapping
        return style
    }

    static func attributes(for payload: TextPayload) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font(for: payload),
            .foregroundColor: UIColor(hex: payload.colorHex),
            .paragraphStyle: paragraphStyle(for: payload),
        ]
        if payload.isUnderlined { attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        return attributes
    }

    static func attributed(_ payload: TextPayload) -> NSAttributedString {
        NSAttributedString(string: payload.text, attributes: attributes(for: payload))
    }

    /// Height the text needs inside a box of `width` points (padding excluded).
    static func contentHeight(for payload: TextPayload, width: CGFloat) -> CGFloat {
        let inner = max(width - TextBoxLayout.padding * 2, 1)
        // A trailing newline still occupies a line while editing.
        let measured = payload.text.hasSuffix("\n") ? payload.text + " " : (payload.text.isEmpty ? " " : payload.text)
        var sample = payload
        sample.text = measured
        let rect = attributed(sample).boundingRect(with: CGSize(width: inner, height: .greatestFiniteMagnitude),
                                                   options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        return ceil(rect.height)
    }

    static func backgroundColor(for payload: TextPayload) -> UIColor? {
        payload.backgroundHex.map { UIColor(hex: $0) }
    }
}
