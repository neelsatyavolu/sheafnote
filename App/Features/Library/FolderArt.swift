import SwiftUI
import SheafnoteCore

/// A stable playful tint per folder, derived from its id (never `hashValue`, which changes per launch).
enum FolderTint {
    static func color(for id: UUID) -> Color {
        let sum = withUnsafeBytes(of: id.uuid) { $0.reduce(0) { ($0 &* 31 &+ Int($1)) & 0xFFFF } }
        return Theme.playful[sum % Theme.playful.count]
    }
}

/// A paper folder with a tab, tinted from the playful set, with the item count on the front.
struct FolderArt: View {
    let tint: Color
    let count: Int

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = w * 0.78
            let front = RoundedRectangle(cornerRadius: w * 0.07, style: .continuous)
            ZStack {
                FolderBackShape()
                    .fill(tint)
                    .overlay(FolderBackShape().fill(Color.black.opacity(0.14)))
                RoundedRectangle(cornerRadius: w * 0.03, style: .continuous)
                    .fill(Theme.sheet)
                    .frame(width: w * 0.84, height: h * 0.5)
                    .offset(y: -h * 0.12)
                front
                    .fill(LinearGradient(colors: [tint, tint.opacity(0.88)], startPoint: .top, endPoint: .bottom))
                    .overlay(front.stroke(Color.white.opacity(0.28), lineWidth: 1))
                    .frame(width: w, height: h * 0.72)
                    .offset(y: h * 0.14)
                Text("\(count)")
                    .font(.system(size: w * 0.17, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(cgColor: CoverPlateStyle.ink.cgColor).opacity(0.78))
                    .offset(y: h * 0.17)
            }
            .frame(width: w, height: h)
            .shadow(color: Theme.shadowColor, radius: 6, x: 0, y: 3)
            .position(x: geo.size.width / 2, y: geo.size.height - h / 2)
        }
        .accessibilityHidden(true)
    }
}

/// Folder silhouette: a rounded body with a tab on the top left.
private struct FolderBackShape: Shape {
    func path(in r: CGRect) -> Path {
        let tabW = r.width * 0.4, tabH = r.height * 0.14, rad = r.width * 0.07
        var p = Path()
        p.move(to: CGPoint(x: rad, y: 0))
        p.addLine(to: CGPoint(x: tabW, y: 0))
        p.addCurve(to: CGPoint(x: tabW + tabH * 0.9, y: tabH),
                   control1: CGPoint(x: tabW + tabH * 0.45, y: 0), control2: CGPoint(x: tabW + tabH * 0.45, y: tabH))
        p.addLine(to: CGPoint(x: r.maxX - rad, y: tabH))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: tabH + rad), control: CGPoint(x: r.maxX, y: tabH))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - rad))
        p.addQuadCurve(to: CGPoint(x: r.maxX - rad, y: r.maxY), control: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: rad, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: 0, y: r.maxY - rad), control: CGPoint(x: 0, y: r.maxY))
        p.addLine(to: CGPoint(x: 0, y: rad))
        p.addQuadCurve(to: CGPoint(x: rad, y: 0), control: .zero)
        p.closeSubpath()
        return p
    }
}
