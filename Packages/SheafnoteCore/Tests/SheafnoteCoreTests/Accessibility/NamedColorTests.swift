import Testing
@testable import SheafnoteCore

@Suite struct NamedColorTests {
    @Test(arguments: [
        ("#000000", NamedColor.black), ("#1B1B1F", .black), ("#FFFFFF", .white), ("#808080", .gray),
        ("#FF0000", .red), ("#E53935", .red), ("#FF9800", .orange), ("#FFEB3B", .yellow), ("#43A047", .green),
        ("#009688", .teal), ("#1A73E8", .blue), ("#8E24AA", .purple), ("#EC407A", .pink), ("#795548", .brown),
        ("1A73E8", .blue), ("#1A73E8FF", .blue),
    ])
    func namesCommonColors(hex: String, expected: NamedColor) {
        #expect(NamedColor.nearest(toHex: hex) == expected)
    }

    @Test func rejectsNonColors() {
        #expect(NamedColor.nearest(toHex: "blue") == nil)
        #expect(NamedColor.nearest(toHex: "#12345") == nil)
        #expect(NamedColor.nearest(toHex: "") == nil)
    }
}
