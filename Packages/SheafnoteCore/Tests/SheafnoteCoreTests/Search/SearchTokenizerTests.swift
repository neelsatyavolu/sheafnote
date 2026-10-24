import XCTest
@testable import SheafnoteCore

final class SearchTokenizerTests: XCTestCase {
    func testSplitsOnPunctuationAndLowercases() {
        XCTAssertEqual(SearchTokenizer.terms(in: "Hello, World! 42-x"), ["hello", "world", "42", "x"])
    }

    func testFoldsDiacritics() {
        XCTAssertEqual(SearchTokenizer.terms(in: "Café Résumé"), ["cafe", "resume"])
        XCTAssertEqual(SearchTokenizer.normalize("ÉCOLE"), "ecole")
    }

    func testTokenRangesPointIntoOriginalText() {
        let text = "ab cd"
        let tokens = SearchTokenizer.tokens(in: text)
        XCTAssertEqual(tokens.map { String(text[$0.range]) }, ["ab", "cd"])
    }

    func testCJKCharactersAreIndividualTokens() {
        XCTAssertEqual(SearchTokenizer.terms(in: "物理学 ok"), ["物", "理", "学", "ok"])
    }

    func testEmptyAndSymbolOnlyTextHaveNoTokens() {
        XCTAssertTrue(SearchTokenizer.terms(in: "").isEmpty)
        XCTAssertTrue(SearchTokenizer.terms(in: " ,.;-- ").isEmpty)
    }

    func testApostropheKeepsWordsApart() {
        XCTAssertEqual(SearchTokenizer.terms(in: "don't"), ["don", "t"])
    }
}
