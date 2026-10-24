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
        CoverDefinition("slate", "Slate", .solid, bg: "3E4A5C", ink: "566379", accent: "C9D3E3"),
        CoverDefinition("moss", "Moss", .solid, bg: "4F6B4A", ink: "63845D", accent: "D5E2C9"),
        CoverDefinition("ember", "Ember", .solid, bg: "C4562F", ink: "D9704A", accent: "FBE3D2"),
        CoverDefinition("plum", "Plum", .solid, bg: "6B3A5B", ink: "84506F", accent: "F0D6E6"),
        CoverDefinition("saffron", "Saffron", .solid, bg: "E3A72F", ink: "F0BC55", accent: "5A3E08"),
        CoverDefinition("harbor", "Harbor", .solid, bg: "2F6F8F", ink: "4488AA", accent: "D2ECF7"),
        CoverDefinition("blush", "Blush", .solid, bg: "E7A9A0", ink: "F0BDB5", accent: "6B2E2A"),
        CoverDefinition("graphite", "Graphite", .solid, bg: "2B2D31", ink: "43464D", accent: "A9AEB8"),
        CoverDefinition("ledger", "Ledger", .stripes, bg: "F1E8D2", ink: "24344D", accent: "B3453A"),
        CoverDefinition("meadow", "Meadow", .diagonal, bg: "7DA867", ink: "5E8C4B", accent: "F4F0D8"),
        CoverDefinition("confetti", "Confetti", .dots, bg: "1F7A78", ink: "F6EBD0", accent: "F2B544"),
        CoverDefinition("blueprint", "Blueprint", .grid, bg: "1D4E89", ink: "7FB0E8", accent: "DDEBFA"),
        CoverDefinition("tide", "Tide", .waves, bg: "3B8EA5", ink: "BFE3EC", accent: "13536A"),
        CoverDefinition("orbit", "Orbit", .rings, bg: "3A3A8C", ink: "8F8FE6", accent: "F4D35E"),
        CoverDefinition("parquet", "Parquet", .checker, bg: "8A5A3C", ink: "A97550", accent: "EBD3B8"),
        CoverDefinition("peaks", "Peaks", .triangles, bg: "493A6B", end: "E07B6A", ink: "2E2447", accent: "FBD9A8"),
        CoverDefinition("herringbone", "Herringbone", .chevrons, bg: "B24A32", ink: "D26A4E", accent: "F7E1CF"),
        CoverDefinition("daybreak", "Daybreak", .sunburst, bg: "F28A5B", end: "F5C26B", ink: "FFE9B8", accent: "8C3B2A"),
        CoverDefinition("scallop", "Scallop", .scales, bg: "8CCFB5", ink: "5FAE93", accent: "1F5A48"),
        CoverDefinition("terrace", "Terrace", .bands, bg: "E6D3A8", ink: "2E7F78", accent: "B8553B"),
    ]

    public static func definition(for id: String) -> CoverDefinition {
        all.first { $0.id == id } ?? all[0]
    }
}
