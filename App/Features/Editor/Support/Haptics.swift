import UIKit

/// Light haptics for chrome actions (tool switch, page add, lasso pick-up). Never used on the writing surface.
@MainActor
enum Haptics {
    static func light() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }
}
