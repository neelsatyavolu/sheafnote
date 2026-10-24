import SwiftUI
import SheafnoteCore

/// User-facing names for core enums. Literal switches keep every string visible to the String Catalog.
extension TemplateKind {
    var title: LocalizedStringResource {
        switch self {
        case .blank: "Blank"
        case .ruledNarrow: "Narrow Ruled"
        case .ruledCollege: "College Ruled"
        case .ruledWide: "Wide Ruled"
        case .gridSmall: "Small Grid"
        case .gridMedium: "Medium Grid"
        case .gridLarge: "Large Grid"
        case .dotted: "Dotted"
        case .cornell: "Cornell"
        case .musicStaff: "Music Staff"
        case .plannerDaily: "Daily Planner"
        case .plannerWeekly: "Weekly Planner"
        case .plannerMonthly: "Monthly Planner"
        case .plannerTodo: "To-Do List"
        }
    }
}

extension TemplateCategory {
    var title: LocalizedStringResource {
        switch self {
        case .blank: "Blank"
        case .ruled: "Ruled"
        case .grid: "Grid"
        case .dotted: "Dotted"
        case .cornell: "Cornell"
        case .music: "Music"
        case .planner: "Planner"
        }
    }
}

extension PaperSize {
    var title: LocalizedStringResource {
        switch self {
        case .a4: "A4"
        case .letter: "US Letter"
        case .a5: "A5"
        case .square: "Square"
        }
    }

    /// "210 × 297 mm" or "8.3 × 11.7 in".
    func dimensionsText(units: MeasurementUnits) -> String {
        let mm = millimetres
        if units.usesMetric {
            return String(localized: "\(Int(mm.width.rounded())) × \(Int(mm.height.rounded())) mm")
        }
        let w = Double(mm.width / 25.4).formatted(.number.precision(.fractionLength(1)))
        let h = Double(mm.height / 25.4).formatted(.number.precision(.fractionLength(1)))
        return String(localized: "\(w) × \(h) in")
    }
}

extension PaperColor {
    var title: LocalizedStringResource {
        switch self {
        case .white: "White"
        case .yellow: "Yellow"
        case .dark: "Dark"
        }
    }
}

extension PageOrientation {
    var title: LocalizedStringResource {
        switch self {
        case .portrait: "Portrait"
        case .landscape: "Landscape"
        }
    }
}

extension CoverDefinition {
    var title: LocalizedStringResource {
        switch id {
        case "slate": "Slate"
        case "moss": "Moss"
        case "ember": "Ember"
        case "plum": "Plum"
        case "saffron": "Saffron"
        case "harbor": "Harbor"
        case "blush": "Blush"
        case "graphite": "Graphite"
        case "ledger": "Ledger"
        case "meadow": "Meadow"
        case "confetti": "Confetti"
        case "blueprint": "Blueprint"
        case "tide": "Tide"
        case "orbit": "Orbit"
        case "parquet": "Parquet"
        case "peaks": "Peaks"
        case "herringbone": "Herringbone"
        case "daybreak": "Daybreak"
        case "scallop": "Scallop"
        case "terrace": "Terrace"
        default: "Cover"
        }
    }
}

extension TemplateStrings {
    /// Planner text in the user's language.
    static var localized: TemplateStrings {
        TemplateStrings(
            weekdays: [String(localized: "Mon"), String(localized: "Tue"), String(localized: "Wed"), String(localized: "Thu"),
                       String(localized: "Fri"), String(localized: "Sat"), String(localized: "Sun")],
            date: String(localized: "Date"), priorities: String(localized: "Priorities"), notes: String(localized: "Notes"),
            toDo: String(localized: "To Do"), weekOf: String(localized: "Week of"), month: String(localized: "Month"))
    }
}

enum MeasurementUnits: String, Codable, CaseIterable {
    case automatic, metric, imperial

    var title: LocalizedStringResource {
        switch self {
        case .automatic: "Automatic"
        case .metric: "Metric"
        case .imperial: "Imperial"
        }
    }

    var usesMetric: Bool {
        switch self {
        case .metric: true
        case .imperial: false
        case .automatic: Locale.current.measurementSystem != .us
        }
    }
}
