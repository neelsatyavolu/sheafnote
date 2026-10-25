import SwiftUI

// iPhone Duo support. The APIs arrive with the iOS 27.1 SDK (SwiftUI 8.0.85, Xcode 27.1); older SDKs, such as the
// Xcode 27.0 beta, compile these helpers to "no fold" and "horizontal bars".

extension GeometryProxy {
    /// The active fold dividing this view into left and right halves (iPhone Duo open like a book), margins included,
    /// in the view's own coordinates. Nil on other devices, when the device is flat or closed, or when the fold runs
    /// across the view horizontally.
    var verticalFold: CGRect? {
        #if canImport(SwiftUI, _version: 8.0.85)
        if #available(iOS 27.1, *) {
            return reservedRegions(kind: .division)
                .first { $0.isActive && $0.frame.height > $0.frame.width && frame(in: .local).intersects($0.frame) }?
                .frame
        }
        #endif
        return nil
    }
}

extension View {
    /// Calls `action` with this view's `verticalFold` now and whenever it changes.
    func onVerticalFoldChange(_ action: @escaping (CGRect?) -> Void) -> some View {
        onGeometryChange(for: CGRect?.self) { $0.verticalFold } action: { action($0) }
    }
}

/// A row of bar controls that becomes a column when the system shows bars vertically at the side of the display
/// (the iPhone Duo's outer display).
struct BarStack<Content: View>: View {
    var spacing: CGFloat
    @ViewBuilder var content: Content

    var body: some View {
        #if canImport(SwiftUI, _version: 8.0.85)
        if #available(iOS 27.1, *) {
            EdgeAwareBarStack(spacing: spacing, content: content)
        } else {
            HStack(spacing: spacing) { content }
        }
        #else
        HStack(spacing: spacing) { content }
        #endif
    }
}

#if canImport(SwiftUI, _version: 8.0.85)
@available(iOS 27.1, *)
private struct EdgeAwareBarStack<Content: View>: View {
    let spacing: CGFloat
    let content: Content
    @Environment(\.toolbarVerticalEdge) private var verticalEdge

    var body: some View {
        let layout = verticalEdge == nil ? AnyLayout(HStackLayout(spacing: spacing)) : AnyLayout(VStackLayout(spacing: spacing))
        layout { content }
    }
}
#endif
