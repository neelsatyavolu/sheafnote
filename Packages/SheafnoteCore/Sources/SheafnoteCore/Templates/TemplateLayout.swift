import CoreGraphics
import Foundation

public enum LineWeight: Sendable, Hashable {
    case hairline, regular, heavy
    public var width: CGFloat {
        switch self {
        case .hairline: 0.5
        case .regular: 0.8
        case .heavy: 1.4
        }
    }
}

public enum LineRole: Sendable, Hashable { case minor, major, accent }

public struct TemplateLine: Sendable, Hashable {
    public var start: CGPoint
    public var end: CGPoint
    public var weight: LineWeight
    public var role: LineRole
}

public struct TemplateBox: Sendable, Hashable {
    public var rect: CGRect
    public var weight: LineWeight
    public var role: LineRole
}

public struct TemplateDot: Sendable, Hashable {
    public var center: CGPoint
    public var radius: CGFloat
}

public struct TemplateLabel: Sendable, Hashable {
    public var text: String
    public var origin: CGPoint      // top-left of the text box
    public var fontSize: CGFloat
}

public enum TemplatePrimitive: Sendable, Hashable {
    case line(TemplateLine), box(TemplateBox), dot(TemplateDot), label(TemplateLabel)
}

/// Resolution-independent description of one page of paper. Origin top-left, points.
public struct TemplateLayout: Sendable, Hashable {
    public var size: CGSize
    public var primitives: [TemplatePrimitive]

    public var lines: [TemplateLine] { primitives.compactMap { if case .line(let l) = $0 { l } else { nil } } }
    public var boxes: [TemplateBox] { primitives.compactMap { if case .box(let b) = $0 { b } else { nil } } }
    public var dots: [TemplateDot] { primitives.compactMap { if case .dot(let d) = $0 { d } else { nil } } }
    public var labels: [TemplateLabel] { primitives.compactMap { if case .label(let l) = $0 { l } else { nil } } }
    public var horizontalLines: [TemplateLine] { lines.filter { $0.start.y == $0.end.y } }
    public var verticalLines: [TemplateLine] { lines.filter { $0.start.x == $0.end.x } }
}
