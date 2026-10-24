import SwiftUI
import SheafnoteCore

/// A search snippet with its matches in bold on a soft highlight.
enum SnippetText {
    static func attributed(_ snippet: SearchSnippet) -> AttributedString {
        var text = AttributedString(snippet.text)
        let count = snippet.text.count
        for range in snippet.ranges where range.lowerBound >= 0 && range.upperBound <= count && !range.isEmpty {
            let lower = text.index(text.startIndex, offsetByCharacters: range.lowerBound)
            let upper = text.index(lower, offsetByCharacters: range.count)
            text[lower..<upper].inlinePresentationIntent = .stronglyEmphasized
            text[lower..<upper].backgroundColor = Theme.sunflower.opacity(0.4)
        }
        return text
    }
}
