import SwiftUI

/// A short hand-drawn ink doodle with one friendly line.
struct LibraryEmptyState: View {
    enum Doodle { case notebook, folder, star, trash }

    let doodle: Doodle
    let title: LocalizedStringKey
    let line: LocalizedStringKey

    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric private var doodleSize: CGFloat = 120

    var body: some View {
        VStack(spacing: 14) {
            DoodleCanvas(doodle: doodle)
                .frame(width: doodleSize, height: doodleSize)
                .scaleEffect(appeared || reduceMotion ? 1 : 0.85)
                .opacity(appeared || reduceMotion ? 1 : 0)
            Text(title).font(Theme.title(.title3)).foregroundStyle(Theme.ink)
            Text(line).font(.body).foregroundStyle(Theme.inkMuted).multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .onAppear { withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) { appeared = true } }
    }
}

/// Smooth Bezier strokes in ink color, drawn on a 100x100 grid.
private struct DoodleCanvas: View {
    let doodle: LibraryEmptyState.Doodle

    var body: some View {
        Canvas { context, size in
            let scale = min(size.width, size.height) / 100
            let style = StrokeStyle(lineWidth: max(2, 2.6 * scale), lineCap: .round, lineJoin: .round)
            for path in Self.strokes(doodle) {
                context.stroke(path.applying(CGAffineTransform(scaleX: scale, y: scale)), with: .color(Theme.ink), style: style)
            }
        }
        .accessibilityHidden(true)
    }

    private static func strokes(_ doodle: LibraryEmptyState.Doodle) -> [Path] {
        switch doodle {
        case .notebook: notebook
        case .folder: folder
        case .star: star
        case .trash: trash
        }
    }

    private typealias Segment = (CGPoint, CGPoint, CGPoint)

    private static func curve(_ start: CGPoint, _ segments: [Segment]) -> Path {
        var p = Path()
        p.move(to: start)
        for s in segments { p.addCurve(to: s.2, control1: s.0, control2: s.1) }
        return p
    }

    private static func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x, y: y) }

    private static let notebook: [Path] = [
        curve(pt(28, 22), [(pt(40, 18), pt(62, 19), pt(74, 22)), (pt(76, 44), pt(77, 66), pt(74, 84)),
                           (pt(62, 87), pt(40, 88), pt(26, 84)), (pt(24, 64), pt(25, 44), pt(28, 22))]),
        curve(pt(38, 21), [(pt(37, 40), pt(38, 64), pt(37, 86))]),
        curve(pt(46, 42), [(pt(52, 34), pt(58, 50), pt(64, 40))]),
        curve(pt(46, 58), [(pt(54, 54), pt(58, 62), pt(64, 57))]),
        curve(pt(84, 12), [(pt(84, 16), pt(84, 18), pt(84, 22))]),
        curve(pt(80, 17), [(pt(82, 17), pt(86, 17), pt(90, 17))]),
    ]

    private static let folder: [Path] = [
        curve(pt(18, 32), [(pt(24, 26), pt(30, 26), pt(38, 27)), (pt(44, 28), pt(46, 36), pt(54, 36)),
                           (pt(64, 36), pt(74, 35), pt(84, 37)), (pt(86, 52), pt(86, 66), pt(83, 78)),
                           (pt(62, 81), pt(40, 80), pt(17, 78)), (pt(15, 62), pt(16, 46), pt(18, 32))]),
        curve(pt(19, 46), [(pt(40, 44), pt(62, 47), pt(85, 45))]),
        curve(pt(42, 62), [(pt(46, 68), pt(56, 68), pt(60, 62))]),
        curve(pt(78, 14), [(pt(80, 18), pt(80, 20), pt(82, 24))]),
        curve(pt(70, 18), [(pt(73, 19), pt(76, 20), pt(80, 21))]),
    ]

    private static let star: [Path] = [
        curve(pt(50, 16), [(pt(54, 30), pt(58, 36), pt(74, 38)), (pt(66, 48), pt(64, 54), pt(70, 76)),
                           (pt(58, 68), pt(54, 66), pt(50, 66)), (pt(46, 66), pt(42, 68), pt(30, 76)),
                           (pt(36, 54), pt(34, 48), pt(26, 38)), (pt(42, 36), pt(46, 30), pt(50, 16))]),
        curve(pt(18, 18), [(pt(20, 20), pt(22, 22), pt(25, 25))]),
        curve(pt(84, 22), [(pt(82, 24), pt(79, 26), pt(76, 28))]),
        curve(pt(40, 88), [(pt(46, 84), pt(54, 92), pt(62, 87))]),
    ]

    private static let trash: [Path] = [
        curve(pt(28, 38), [(pt(29, 54), pt(31, 70), pt(33, 84)), (pt(44, 86), pt(56, 86), pt(67, 84)),
                           (pt(69, 70), pt(71, 54), pt(72, 38))]),
        curve(pt(22, 34), [(pt(38, 31), pt(62, 31), pt(78, 34))]),
        curve(pt(42, 32), [(pt(42, 24), pt(46, 22), pt(50, 22)), (pt(54, 22), pt(58, 24), pt(58, 32))]),
        curve(pt(43, 46), [(pt(44, 56), pt(44, 66), pt(45, 74))]),
        curve(pt(57, 46), [(pt(56, 56), pt(56, 66), pt(55, 74))]),
        curve(pt(80, 14), [(pt(86, 10), pt(90, 18), pt(86, 22))]),
    ]
}
