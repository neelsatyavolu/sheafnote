import Foundation

public enum TemplateCategory: String, Codable, CaseIterable, Sendable {
    case blank, ruled, grid, dotted, cornell, music, planner
}

public enum TemplateKind: String, Codable, CaseIterable, Sendable {
    case blank
    case ruledNarrow, ruledCollege, ruledWide
    case gridSmall, gridMedium, gridLarge
    case dotted
    case cornell
    case musicStaff
    case plannerDaily, plannerWeekly, plannerMonthly, plannerTodo

    public var category: TemplateCategory {
        switch self {
        case .blank: .blank
        case .ruledNarrow, .ruledCollege, .ruledWide: .ruled
        case .gridSmall, .gridMedium, .gridLarge: .grid
        case .dotted: .dotted
        case .cornell: .cornell
        case .musicStaff: .music
        case .plannerDaily, .plannerWeekly, .plannerMonthly, .plannerTodo: .planner
        }
    }

    /// English display name (the app localizes through its String Catalog using this as the key).
    public var displayName: String {
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

public extension TemplateCategory {
    var displayName: String {
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

    var kinds: [TemplateKind] { TemplateKind.allCases.filter { $0.category == self } }
}

/// What a page's paper looks like. Drawn as vectors by `TemplateRenderer`.
public struct TemplateSpec: Codable, Hashable, Sendable {
    public var kind: TemplateKind
    public var version: Int

    public init(kind: TemplateKind, version: Int = 1) {
        self.kind = kind
        self.version = version
    }

    public static let blank = TemplateSpec(kind: .blank)
}

/// Text the planner templates print on the page. Defaults are English; the app passes localized values.
public struct TemplateStrings: Sendable, Hashable {
    public var weekdays: [String]       // Monday first, 7 entries
    public var date: String
    public var priorities: String
    public var notes: String
    public var toDo: String
    public var weekOf: String
    public var month: String

    public init(weekdays: [String], date: String, priorities: String, notes: String,
                toDo: String, weekOf: String, month: String) {
        self.weekdays = weekdays
        self.date = date
        self.priorities = priorities
        self.notes = notes
        self.toDo = toDo
        self.weekOf = weekOf
        self.month = month
    }

    public static let english = TemplateStrings(
        weekdays: ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"],
        date: "Date", priorities: "Priorities", notes: "Notes", toDo: "To Do", weekOf: "Week of", month: "Month")
}
