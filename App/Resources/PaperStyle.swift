import SwiftUI
import UIKit

/// Shared styling for sheets, forms and empty states. Built only from `Theme` tokens (see DESIGN.md).
extension View {
    /// Warm paper background behind a `List` or `Form`, with raised rows and rule-colored separators.
    func paperList() -> some View {
        scrollContentBackground(.hidden)
            .background(Theme.paper)
            .listRowBackground(Theme.paperRaised)
            .listRowSeparatorTint(Theme.rule)
    }

    /// Raised row surface and separators for the rows of the view this is applied to (use inside a List/Form).
    func paperRows() -> some View {
        listRowBackground(Theme.paperRaised).listRowSeparatorTint(Theme.rule)
    }

    /// Section header style: rounded semibold in ink, not forced to uppercase.
    func paperHeader() -> some View {
        font(Theme.title(.headline)).textCase(nil).foregroundStyle(Theme.ink)
    }

    /// Card surface: paperRaised, 14pt continuous corners, hairline rule outline.
    func paperCard(shadow: Bool = false) -> some View {
        background(Theme.paperRaised, in: RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous).stroke(Theme.rule, lineWidth: 1))
            .shadow(color: shadow ? Theme.shadowColor : .clear, radius: 8, y: 3)
    }
}

/// Light haptics for primary actions.
enum Haptics {
    @MainActor static func light() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

/// A few hand-drawn ink strokes for empty states.
enum DoodleKind {
    case search, cards, tray, lock

    /// Strokes in a unit square.
    fileprivate var strokes: [Path] {
        switch self {
        case .search:
            return [
                Path { p in
                    p.addEllipse(in: CGRect(x: 0.14, y: 0.12, width: 0.5, height: 0.5))
                },
                Path { p in
                    p.move(to: CGPoint(x: 0.54, y: 0.56))
                    p.addQuadCurve(to: CGPoint(x: 0.88, y: 0.9), control: CGPoint(x: 0.74, y: 0.66))
                },
                Path { p in
                    p.move(to: CGPoint(x: 0.28, y: 0.34))
                    p.addCurve(to: CGPoint(x: 0.5, y: 0.34), control1: CGPoint(x: 0.34, y: 0.22), control2: CGPoint(x: 0.44, y: 0.46))
                },
            ]
        case .cards:
            return [
                Path { p in
                    p.move(to: CGPoint(x: 0.16, y: 0.3))
                    p.addQuadCurve(to: CGPoint(x: 0.7, y: 0.22), control: CGPoint(x: 0.4, y: 0.16))
                    p.addLine(to: CGPoint(x: 0.76, y: 0.7))
                    p.addQuadCurve(to: CGPoint(x: 0.2, y: 0.78), control: CGPoint(x: 0.5, y: 0.84))
                    p.closeSubpath()
                },
                Path { p in
                    p.move(to: CGPoint(x: 0.3, y: 0.42))
                    p.addCurve(to: CGPoint(x: 0.6, y: 0.4), control1: CGPoint(x: 0.4, y: 0.36), control2: CGPoint(x: 0.5, y: 0.46))
                },
                Path { p in
                    p.move(to: CGPoint(x: 0.32, y: 0.58))
                    p.addQuadCurve(to: CGPoint(x: 0.58, y: 0.56), control: CGPoint(x: 0.46, y: 0.64))
                },
                Path { p in
                    p.move(to: CGPoint(x: 0.84, y: 0.12))
                    p.addLine(to: CGPoint(x: 0.9, y: 0.26))
                    p.move(to: CGPoint(x: 0.78, y: 0.2))
                    p.addLine(to: CGPoint(x: 0.94, y: 0.18))
                },
            ]
        case .tray:
            return [
                Path { p in
                    p.move(to: CGPoint(x: 0.12, y: 0.52))
                    p.addLine(to: CGPoint(x: 0.28, y: 0.52))
                    p.addQuadCurve(to: CGPoint(x: 0.4, y: 0.66), control: CGPoint(x: 0.3, y: 0.66))
                    p.addLine(to: CGPoint(x: 0.6, y: 0.66))
                    p.addQuadCurve(to: CGPoint(x: 0.72, y: 0.52), control: CGPoint(x: 0.7, y: 0.66))
                    p.addLine(to: CGPoint(x: 0.88, y: 0.52))
                },
                Path { p in
                    p.move(to: CGPoint(x: 0.12, y: 0.52))
                    p.addLine(to: CGPoint(x: 0.2, y: 0.24))
                    p.addQuadCurve(to: CGPoint(x: 0.8, y: 0.24), control: CGPoint(x: 0.5, y: 0.2))
                    p.addLine(to: CGPoint(x: 0.88, y: 0.52))
                    p.addLine(to: CGPoint(x: 0.88, y: 0.78))
                    p.addQuadCurve(to: CGPoint(x: 0.12, y: 0.78), control: CGPoint(x: 0.5, y: 0.84))
                    p.closeSubpath()
                },
            ]
        case .lock:
            return [
                Path { p in
                    p.move(to: CGPoint(x: 0.26, y: 0.46))
                    p.addQuadCurve(to: CGPoint(x: 0.76, y: 0.44), control: CGPoint(x: 0.5, y: 0.4))
                    p.addLine(to: CGPoint(x: 0.78, y: 0.86))
                    p.addQuadCurve(to: CGPoint(x: 0.24, y: 0.88), control: CGPoint(x: 0.5, y: 0.92))
                    p.closeSubpath()
                },
                Path { p in
                    p.move(to: CGPoint(x: 0.34, y: 0.45))
                    p.addCurve(to: CGPoint(x: 0.68, y: 0.45), control1: CGPoint(x: 0.3, y: 0.1), control2: CGPoint(x: 0.72, y: 0.1))
                },
                Path { p in
                    p.addEllipse(in: CGRect(x: 0.47, y: 0.58, width: 0.07, height: 0.07))
                },
            ]
        }
    }
}

struct Doodle: View {
    let kind: DoodleKind
    var size: CGFloat = 96

    var body: some View {
        Canvas { context, canvas in
            let side = min(canvas.width, canvas.height)
            let transform = CGAffineTransform(scaleX: side, y: side)
            for stroke in kind.strokes {
                context.stroke(stroke.applying(transform), with: .color(Theme.ink),
                               style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Doodle, rounded title and one friendly line.
struct DoodleEmptyState: View {
    let kind: DoodleKind
    let title: Text
    let message: Text

    var body: some View {
        VStack(spacing: 10) {
            Doodle(kind: kind)
            title.font(Theme.title(.title3)).foregroundStyle(Theme.ink)
            message.font(.subheadline).foregroundStyle(Theme.inkMuted).multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: 360)
    }
}
