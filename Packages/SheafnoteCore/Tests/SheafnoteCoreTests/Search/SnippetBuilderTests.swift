import XCTest
@testable import SheafnoteCore

final class SnippetBuilderTests: XCTestCase {
    private func highlighted(_ s: SearchSnippet) -> [String] {
        s.ranges.map { r in
            let chars = Array(s.text)
            return String(chars[r])
        }
    }

    func testShortTextIsKeptWhole() {
        let s = SnippetBuilder.snippet(in: "Newton laws of motion", terms: ["laws"])
        XCTAssertEqual(s.text, "Newton laws of motion")
        XCTAssertEqual(highlighted(s), ["laws"])
    }

    func testPrefixTermHighlightsWholeWord() {
        let s = SnippetBuilder.snippet(in: "Thermodynamics today", terms: ["thermo"])
        XCTAssertEqual(highlighted(s), ["Thermodynamics"])
    }

    func testLongTextIsWindowedAroundFirstMatchWithEllipses() {
        let filler = String(repeating: "lorem ipsum ", count: 30)
        let text = filler + "needle " + filler
        let s = SnippetBuilder.snippet(in: text, terms: ["needle"], maxLength: 60)
        XCTAssertTrue(s.text.hasPrefix("…"))
        XCTAssertTrue(s.text.hasSuffix("…"))
        XCTAssertLessThanOrEqual(s.text.count, 70)
        XCTAssertEqual(highlighted(s), ["needle"])
    }

    func testNewlinesBecomeSpaces() {
        let s = SnippetBuilder.snippet(in: "first line\nsecond line", terms: ["second"])
        XCTAssertEqual(s.text, "first line second line")
        XCTAssertEqual(highlighted(s), ["second"])
    }

    func testNoMatchGivesLeadingTextWithoutRanges() {
        let s = SnippetBuilder.snippet(in: "alpha beta", terms: ["zzz"])
        XCTAssertEqual(s.text, "alpha beta")
        XCTAssertTrue(s.ranges.isEmpty)
    }

    func testDiacriticMatch() {
        let s = SnippetBuilder.snippet(in: "Visit the Café", terms: ["cafe"])
        XCTAssertEqual(highlighted(s), ["Café"])
    }
}
