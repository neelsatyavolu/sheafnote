import UIKit

/// Navigation titles (Documents, Sheafnote, folder names) use SF Pro Rounded semibold, per DESIGN.md.
enum NavigationTitleStyle {
    @MainActor static func apply() {
        let standard = UINavigationBarAppearance()
        standard.configureWithDefaultBackground()
        let edge = UINavigationBarAppearance()
        edge.configureWithTransparentBackground()
        for appearance in [standard, edge] {
            appearance.titleTextAttributes = [.font: rounded(.headline)]
            appearance.largeTitleTextAttributes = [.font: rounded(.largeTitle)]
        }
        let bar = UINavigationBar.appearance()
        bar.standardAppearance = standard
        bar.compactAppearance = standard
        bar.scrollEdgeAppearance = edge
    }

    private static func rounded(_ style: UIFont.TextStyle) -> UIFont {
        let base = UIFont.preferredFont(forTextStyle: style)
        let descriptor = base.fontDescriptor.withDesign(.rounded)?
            .addingAttributes([.traits: [UIFontDescriptor.TraitKey.weight: UIFont.Weight.semibold]])
        return UIFont(descriptor: descriptor ?? base.fontDescriptor, size: base.pointSize)
    }
}
