import CoreGraphics
import Foundation

/// Builds the vector layout for a template at a given page size.
public enum TemplateLayoutBuilder {
    public static func layout(for spec: TemplateSpec, size: CGSize, strings: TemplateStrings = .english) -> TemplateLayout {
        let prims: [TemplatePrimitive]
        switch spec.kind {
        case .blank: prims = []
        case .ruledNarrow, .ruledCollege, .ruledWide: prims = ruled(spec.kind, size)
        case .gridSmall, .gridMedium, .gridLarge: prims = grid(TemplateMetrics.gridSpacing(spec.kind), size)
        case .dotted: prims = dotted(size)
        case .cornell: prims = cornell(size)
        case .musicStaff: prims = staff(size)
        case .plannerDaily: prims = PlannerLayouts.daily(size, strings)
        case .plannerWeekly: prims = PlannerLayouts.weekly(size, strings)
        case .plannerMonthly: prims = PlannerLayouts.monthly(size, strings)
        case .plannerTodo: prims = PlannerLayouts.todo(size, strings)
        }
        return TemplateLayout(size: size, primitives: prims)
    }

    static func hLine(_ y: CGFloat, _ x0: CGFloat, _ x1: CGFloat, _ weight: LineWeight = .hairline,
                      _ role: LineRole = .minor) -> TemplatePrimitive {
        .line(TemplateLine(start: CGPoint(x: x0, y: y), end: CGPoint(x: x1, y: y), weight: weight, role: role))
    }

    static func vLine(_ x: CGFloat, _ y0: CGFloat, _ y1: CGFloat, _ weight: LineWeight = .hairline,
                      _ role: LineRole = .minor) -> TemplatePrimitive {
        .line(TemplateLine(start: CGPoint(x: x, y: y0), end: CGPoint(x: x, y: y1), weight: weight, role: role))
    }

    /// y positions of ruled lines from `top` while they fit above `bottom`.
    static func rows(top: CGFloat, bottom: CGFloat, spacing: CGFloat) -> [CGFloat] {
        guard spacing > 0, bottom >= top else { return [] }
        let count = Int(((bottom - top) / spacing).rounded(.down))
        return (0...count).map { top + CGFloat($0) * spacing }
    }

    static func ruled(_ kind: TemplateKind, _ size: CGSize) -> [TemplatePrimitive] {
        let s = TemplateMetrics.ruledSpacing(kind)
        let inset = TemplateMetrics.sideInset
        var out = rows(top: TemplateMetrics.ruledTop, bottom: size.height - TemplateMetrics.ruledBottom, spacing: s)
            .map { hLine($0, inset, size.width - inset) }
        if kind == .ruledCollege {
            out.append(vLine(TemplateMetrics.collegeMarginX, 0, size.height, .regular, .accent))
        }
        return out
    }

    /// Grid positions centred on the page so margins are symmetric.
    static func gridPositions(length: CGFloat, spacing: CGFloat) -> [CGFloat] {
        let n = Int((length / spacing).rounded(.down))
        let lead = (length - CGFloat(n) * spacing) / 2
        return (0...n).map { lead + CGFloat($0) * spacing }
    }

    static func grid(_ s: CGFloat, _ size: CGSize) -> [TemplatePrimitive] {
        let xs = gridPositions(length: size.width, spacing: s)
        let ys = gridPositions(length: size.height, spacing: s)
        let x0 = xs.first ?? 0, x1 = xs.last ?? size.width
        let y0 = ys.first ?? 0, y1 = ys.last ?? size.height
        return xs.map { vLine($0, y0, y1) } + ys.map { hLine($0, x0, x1) }
    }

    static func dotted(_ size: CGSize) -> [TemplatePrimitive] {
        let s = TemplateMetrics.dotSpacing
        let xs = gridPositions(length: size.width, spacing: s)
        let ys = gridPositions(length: size.height, spacing: s)
        return ys.flatMap { y in
            xs.map { x in .dot(TemplateDot(center: CGPoint(x: x, y: y), radius: TemplateMetrics.dotRadius)) }
        }
    }

    static func cornell(_ size: CGSize) -> [TemplatePrimitive] {
        let headerY = size.height * TemplateMetrics.cornellHeaderFraction
        let summaryY = size.height * TemplateMetrics.cornellSummaryFraction
        let cueX = size.width * TemplateMetrics.cornellCueFraction
        var out: [TemplatePrimitive] = [
            hLine(headerY, 0, size.width, .heavy, .accent),
            hLine(summaryY, 0, size.width, .heavy, .accent),
            vLine(cueX, headerY, summaryY, .heavy, .accent),
        ]
        let rowYs = rows(top: headerY + TemplateMetrics.cornellLineSpacing,
                         bottom: summaryY - TemplateMetrics.cornellLineSpacing / 2,
                         spacing: TemplateMetrics.cornellLineSpacing)
        out += rowYs.map { hLine($0, cueX + 12, size.width - TemplateMetrics.sideInset) }
        return out
    }

    static func staff(_ size: CGSize) -> [TemplatePrimitive] {
        let height = TemplateMetrics.staffLineGap * 4
        let pitch = TemplateMetrics.staffPitch
        let inset = TemplateMetrics.staffInset
        var out: [TemplatePrimitive] = []
        var top = TemplateMetrics.staffTop
        while top + height <= size.height - TemplateMetrics.staffBottom {
            for i in 0..<5 {
                out.append(hLine(top + CGFloat(i) * TemplateMetrics.staffLineGap, inset, size.width - inset, .regular, .major))
            }
            out.append(vLine(inset, top, top + height, .regular, .major))
            top += pitch
        }
        return out
    }
}
