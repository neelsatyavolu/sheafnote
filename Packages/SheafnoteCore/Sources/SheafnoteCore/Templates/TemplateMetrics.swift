import CoreGraphics

/// All paper measurements in one place (points).
public enum TemplateMetrics {
    public static let ruledTop: CGFloat = 64
    public static let ruledBottom: CGFloat = 36
    public static let sideInset: CGFloat = 24
    public static let collegeMarginX: CGFloat = 72

    public static func ruledSpacing(_ kind: TemplateKind) -> CGFloat {
        switch kind {
        case .ruledNarrow: 18
        case .ruledCollege: 22
        default: 28
        }
    }

    public static func gridSpacing(_ kind: TemplateKind) -> CGFloat {
        switch kind {
        case .gridSmall: 14
        case .gridMedium: 20
        default: 28
        }
    }

    public static let dotSpacing: CGFloat = 20
    public static let dotRadius: CGFloat = 1.1

    public static let cornellHeaderFraction: CGFloat = 0.12
    public static let cornellCueFraction: CGFloat = 0.27
    public static let cornellSummaryFraction: CGFloat = 0.82
    public static let cornellLineSpacing: CGFloat = 24

    public static let staffLineGap: CGFloat = 8
    public static let staffPitch: CGFloat = 80
    public static let staffTop: CGFloat = 72
    public static let staffBottom: CGFloat = 40
    public static let staffInset: CGFloat = 36

    public static let plannerMargin: CGFloat = 28
    public static let plannerHeader: CGFloat = 56
    public static let plannerFirstHour = 6
    public static let plannerHourCount = 16
    public static let monthRows = 6
    public static let todoRowHeight: CGFloat = 36
    public static let todoBox: CGFloat = 14
}
