import CoreGraphics
import Foundation

/// Planner pages are composed from the same primitives as the other papers.
enum PlannerLayouts {
    typealias B = TemplateLayoutBuilder
    static let m = TemplateMetrics.plannerMargin

    static func label(_ text: String, _ x: CGFloat, _ y: CGFloat, _ size: CGFloat = 11) -> TemplatePrimitive {
        .label(TemplateLabel(text: text, origin: CGPoint(x: x, y: y), fontSize: size))
    }

    static func box(_ rect: CGRect, _ role: LineRole = .minor) -> TemplatePrimitive {
        .box(TemplateBox(rect: rect, weight: .regular, role: role))
    }

    static func header(_ title: String, _ size: CGSize) -> [TemplatePrimitive] {
        let y = m + TemplateMetrics.plannerHeader - 12
        return [label(title, m, m + 8, 15), B.hLine(y, m, size.width - m, .heavy, .accent)]
    }

    static var bodyTop: CGFloat { m + TemplateMetrics.plannerHeader }

    static func daily(_ size: CGSize, _ t: TemplateStrings) -> [TemplatePrimitive] {
        var out = header(t.date, size)
        let split = m + (size.width - 2 * m) * 0.6
        let bottom = size.height - m
        let rowH = (bottom - bodyTop) / CGFloat(TemplateMetrics.plannerHourCount)
        for i in 0..<TemplateMetrics.plannerHourCount {
            let y = bodyTop + CGFloat(i) * rowH
            out.append(B.hLine(y, m, split - 12))
            out.append(label("\(TemplateMetrics.plannerFirstHour + i)", m + 2, y + 3, 9))
        }
        out.append(B.hLine(bottom, m, split - 12))
        out.append(B.vLine(split, bodyTop, bottom, .regular, .major))
        let rx = split + 12
        out.append(label(t.priorities, rx, bodyTop + 2, 11))
        for i in 0..<3 {
            let y = bodyTop + 28 + CGFloat(i) * 30
            out.append(box(CGRect(x: rx, y: y, width: 12, height: 12)))
            out.append(B.hLine(y + 14, rx + 20, size.width - m))
        }
        let notesTop = bodyTop + 28 + 3 * 30 + 12
        out.append(label(t.notes, rx, notesTop, 11))
        out += B.rows(top: notesTop + 36, bottom: bottom, spacing: 24).map { B.hLine($0, rx, size.width - m) }
        return out
    }

    static func weekly(_ size: CGSize, _ t: TemplateStrings) -> [TemplatePrimitive] {
        var out = header(t.weekOf, size)
        let cols = 2, rowsCount = 4
        let gap: CGFloat = 8
        let cellW = (size.width - 2 * m - gap * CGFloat(cols - 1)) / CGFloat(cols)
        let cellH = (size.height - m - bodyTop - gap * CGFloat(rowsCount - 1)) / CGFloat(rowsCount)
        let names = t.weekdays.prefix(7) + [t.notes]
        for (i, name) in names.enumerated() {
            let r = CGRect(x: m + CGFloat(i % cols) * (cellW + gap), y: bodyTop + CGFloat(i / cols) * (cellH + gap),
                           width: cellW, height: cellH)
            out.append(box(r))
            out.append(label(name, r.minX + 6, r.minY + 5, 10))
            out += B.rows(top: r.minY + 34, bottom: r.maxY - 6, spacing: 24).map { B.hLine($0, r.minX + 6, r.maxX - 6) }
        }
        return out
    }

    static func monthly(_ size: CGSize, _ t: TemplateStrings) -> [TemplatePrimitive] {
        var out = header(t.month, size)
        let cols = 7, rowsCount = TemplateMetrics.monthRows
        let headerRow: CGFloat = 22
        let gridTop = bodyTop + headerRow
        let cellW = (size.width - 2 * m) / CGFloat(cols)
        let cellH = (size.height - m - gridTop) / CGFloat(rowsCount)
        for c in 0..<cols {
            out.append(label(t.weekdays[c % t.weekdays.count], m + CGFloat(c) * cellW + 6, bodyTop + 4, 10))
        }
        for r in 0..<rowsCount {
            for c in 0..<cols {
                out.append(box(CGRect(x: m + CGFloat(c) * cellW, y: gridTop + CGFloat(r) * cellH, width: cellW, height: cellH)))
            }
        }
        return out
    }

    static func todo(_ size: CGSize, _ t: TemplateStrings) -> [TemplatePrimitive] {
        var out = header(t.toDo, size)
        let h = TemplateMetrics.todoRowHeight
        let count = max(0, Int(((size.height - m - bodyTop) / h).rounded(.down)))
        for i in 0..<count {
            let y = bodyTop + CGFloat(i) * h
            out.append(box(CGRect(x: m, y: y + (h - TemplateMetrics.todoBox) / 2 + 2,
                                  width: TemplateMetrics.todoBox, height: TemplateMetrics.todoBox)))
            out.append(B.hLine(y + h, m + TemplateMetrics.todoBox + 10, size.width - m))
        }
        return out
    }
}
