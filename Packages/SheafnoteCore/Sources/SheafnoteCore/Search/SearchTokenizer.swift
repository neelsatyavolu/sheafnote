import Foundation

/// One searchable word: its normalized form and where it sits in the original text.
public struct SearchToken: Hashable, Sendable {
    public let term: String
    public let range: Range<String.Index>
}

/// Splits text into lowercase, diacritic-free words. Letters and digits form words; everything else separates them.
/// Han, Hiragana and Katakana have no spaces, so each of those characters is its own word.
public enum SearchTokenizer {
    public static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    public static func terms(in text: String) -> [String] { tokens(in: text).map(\.term) }

    public static func tokens(in text: String) -> [SearchToken] {
        var result: [SearchToken] = []
        var start: String.Index?
        var index = text.startIndex
        func close(at end: String.Index) {
            guard let s = start else { return }
            result.append(SearchToken(term: normalize(String(text[s..<end])), range: s..<end))
            start = nil
        }
        while index < text.endIndex {
            let ch = text[index]
            let next = text.index(after: index)
            if isWordCharacter(ch) {
                if isUnspaced(ch) {
                    close(at: index)
                    result.append(SearchToken(term: normalize(String(ch)), range: index..<next))
                } else if start == nil {
                    start = index
                }
            } else {
                close(at: index)
            }
            index = next
        }
        close(at: text.endIndex)
        return result
    }

    private static func isWordCharacter(_ ch: Character) -> Bool { ch.isLetter || ch.isNumber }

    private static func isUnspaced(_ ch: Character) -> Bool {
        guard let v = ch.unicodeScalars.first?.value else { return false }
        return (0x3400...0x4DBF).contains(v) || (0x4E00...0x9FFF).contains(v) || (0x3040...0x30FF).contains(v)
    }
}
