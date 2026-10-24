import SwiftUI

/// Sheafnote's visual tokens. See DESIGN.md: warm paper and ink, bright and playful.
/// Views use these instead of literal colors, radii or font designs.
enum Theme {
    // MARK: Surfaces and text (light/dark pairs live in Assets.xcassets)

    static let paper = Color("Paper")
    static let paperRaised = Color("PaperRaised")
    static let ink = Color("Ink")
    static let inkMuted = Color("InkMuted")
    static let rule = Color("Rule")
    static let accent = Color.accentColor
    /// A physical sheet of paper drawn inside artwork (folder inserts); cream in both modes.
    static let sheet = Color(red: 1, green: 0xFD / 255, blue: 0xF8 / 255)

    // MARK: Playful set (covers, folders, presets, stickers)

    static let sunflower = Color(red: 0xFF / 255, green: 0xC9 / 255, blue: 0x3C / 255)
    static let mint = Color(red: 0x3C / 255, green: 0xC9 / 255, blue: 0xA0 / 255)
    static let sky = Color(red: 0x3D / 255, green: 0x9B / 255, blue: 0xFF / 255)
    static let lilac = Color(red: 0xA7 / 255, green: 0x7B / 255, blue: 0xFF / 255)
    static let bubblegum = Color(red: 0xFF / 255, green: 0x6F / 255, blue: 0xA8 / 255)
    static let tangerine = Color(red: 0xF2 / 255, green: 0x54 / 255, blue: 0x2D / 255)

    static let playful: [Color] = [tangerine, sunflower, mint, sky, lilac, bubblegum]

    // MARK: Shape

    enum Radius {
        static let tile: CGFloat = 14
        static let control: CGFloat = 10
        static let cover: CGFloat = 6
    }

    /// Soft, warm shadow for covers and floating panels only.
    static let shadowColor = Color("Ink").opacity(0.12)

    // MARK: Type

    /// Titles and section headers.
    static func title(_ style: Font.TextStyle = .title2) -> Font {
        .system(style, design: .rounded).weight(.semibold)
    }

    /// Notebook titles on covers and in the editor bar.
    static func notebookTitle(_ style: Font.TextStyle = .headline) -> Font {
        .system(style, design: .serif).weight(.semibold)
    }
}
