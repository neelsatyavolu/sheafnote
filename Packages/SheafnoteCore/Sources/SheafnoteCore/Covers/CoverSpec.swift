import Foundation

/// What a notebook cover looks like: a reference into the built-in catalog.
public struct CoverSpec: Codable, Hashable, Sendable {
    public var coverID: String
    public var version: Int

    public init(coverID: String, version: Int = 1) {
        self.coverID = coverID
        self.version = version
    }

    public static let `default` = CoverSpec(coverID: "slate")
    public var definition: CoverDefinition { CoverCatalog.definition(for: coverID) }
}

public enum CoverPattern: String, Codable, Sendable, CaseIterable {
    case solid, stripes, diagonal, dots, grid, waves, rings, checker, triangles, chevrons, sunburst, scales, bands
}

public struct CoverDefinition: Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let pattern: CoverPattern
    public let background: RGBAColor
    public let backgroundEnd: RGBAColor?   // vertical gradient when set
    public let ink: RGBAColor              // pattern color
    public let accent: RGBAColor           // border / second pattern color

    init(_ id: String, _ name: String, _ pattern: CoverPattern, bg: String, end: String? = nil,
         ink: String, accent: String) {
        self.id = id
        self.name = name
        self.pattern = pattern
        self.background = RGBAColor(hex: bg)!
        self.backgroundEnd = end.flatMap { RGBAColor(hex: $0) }
        self.ink = RGBAColor(hex: ink)!
        self.accent = RGBAColor(hex: accent)!
    }
}

/// The built-in covers. All artwork is original and drawn in code by `CoverRenderer`.
public enum CoverCatalog {
    public static let all: [CoverDefinition] = [
        CoverDefinition("slate", "Slate", .solid, bg: "4B4F6B", ink: "62668A", accent: "D9DBF0"),
        CoverDefinition("moss", "Moss", .solid, bg: "4E7A58", ink: "639070", accent: "DCEBD2"),
        CoverDefinition("ember", "Ember", .solid, bg: "F2542D", ink: "F7704C", accent: "FFE6D8"),
        CoverDefinition("plum", "Plum", .solid, bg: "7A3F66", ink: "92557D", accent: "F5DAEA"),
        CoverDefinition("saffron", "Saffron", .solid, bg: "FFC93C", ink: "FFD768", accent: "5A3E08"),
        CoverDefinition("harbor", "Harbor", .solid, bg: "3D9BFF", ink: "65B0FF", accent: "E8F3FF"),
        CoverDefinition("blush", "Blush", .solid, bg: "FF6FA8", ink: "FF8EB9", accent: "FFE3EF"),
        CoverDefinition("graphite", "Graphite", .solid, bg: "3A322C", ink: "50463E", accent: "D8CBBB"),
        CoverDefinition("ledger", "Ledger", .stripes, bg: "F6EBD3", ink: "2F2D52", accent: "F2542D"),
        CoverDefinition("meadow", "Meadow", .diagonal, bg: "3CC9A0", ink: "2FB08A", accent: "FFF6DC"),
        CoverDefinition("confetti", "Confetti", .dots, bg: "A77BFF", ink: "FFF1D6", accent: "FFC93C"),
        CoverDefinition("blueprint", "Blueprint", .grid, bg: "2E6FD8", ink: "8EBBFF", accent: "EAF3FF"),
        CoverDefinition("tide", "Tide", .waves, bg: "2FB5B0", ink: "CFF5EE", accent: "14615D"),
        CoverDefinition("orbit", "Orbit", .rings, bg: "7A56E0", ink: "B79CFF", accent: "FFC93C"),
        CoverDefinition("parquet", "Parquet", .checker, bg: "9A5B3A", ink: "B8714B", accent: "F0D9BC"),
        CoverDefinition("peaks", "Peaks", .triangles, bg: "6B4A9E", end: "FF6FA8", ink: "3E2A66", accent: "FFE3A3"),
        CoverDefinition("herringbone", "Herringbone", .chevrons, bg: "C2412A", ink: "E0654A", accent: "FBE5D2"),
        CoverDefinition("daybreak", "Daybreak", .sunburst, bg: "FF8A5B", end: "FFC93C", ink: "FFF0C2", accent: "9A3A22"),
        CoverDefinition("scallop", "Scallop", .scales, bg: "7ADBC0", ink: "4FBFA0", accent: "1F6B55"),
        CoverDefinition("terrace", "Terrace", .bands, bg: "F3DFB0", ink: "2E8F86", accent: "F2542D"),
    ]

    public static func definition(for id: String) -> CoverDefinition {
        all.first { $0.id == id } ?? all[0]
    }
}

/// Colors of the cream label plate the app draws over a cover (fixed in light and dark; a plate is paper).
public enum CoverPlateStyle {
    public static let fill = RGBAColor(hex: "FFFDF8")!
    public static let ink = RGBAColor(hex: "2B2420")!
}
