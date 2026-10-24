import Foundation

/// Cuts a short excerpt around the first match and reports which characters to highlight.
public enum SnippetBuilder {
    /// `terms` are normalized query terms; a word matches when it starts with any of them.
    public static func snippet(in text: String, terms: [String], maxLength: Int = 120) -> SearchSnippet {
        let flat = String(text.map { $0.isNewline ? " " : $0 })
        let chars = Array(flat)
        let matches = matchingRanges(in: flat, terms: terms)
        guard let first = matches.first else {
            return SearchSnippet(text: truncated(chars, maxLength: maxLength), ranges: [])
        }
        var lower = 0
        var upper = chars.count
        if chars.count > maxLength {
            lower = max(0, first.lowerBound - maxLength / 3)
            upper = min(chars.count, lower + maxLength)
            lower = wordStart(chars, from: lower)
            upper = wordEnd(chars, from: upper)
        }
        let prefix = lower > 0 ? "…" : ""
        let suffix = upper < chars.count ? "…" : ""
        let body = String(chars[lower..<upper]).trimmingCharacters(in: .whitespaces)
        let trimmedLead = chars[lower..<upper].prefix { $0 == " " }.count
        let shift = prefix.count - (lower + trimmedLead)
        let ranges = matches.compactMap { r -> Range<Int>? in
            guard r.lowerBound >= lower + trimmedLead, r.upperBound <= upper else { return nil }
            return (r.lowerBound + shift)..<(r.upperBound + shift)
        }
        return SearchSnippet(text: prefix + body + suffix, ranges: ranges)
    }

    /// Character-offset ranges of every word in `text` that starts with one of `terms`.
    public static func matchingRanges(in text: String, terms: [String]) -> [Range<Int>] {
        guard !terms.isEmpty else { return [] }
        return SearchTokenizer.tokens(in: text).compactMap { token in
            guard terms.contains(where: { token.term.hasPrefix($0) }) else { return nil }
            let lower = text.distance(from: text.startIndex, to: token.range.lowerBound)
            let upper = text.distance(from: text.startIndex, to: token.range.upperBound)
            return lower..<upper
        }
    }

    private static func truncated(_ chars: [Character], maxLength: Int) -> String {
        guard chars.count > maxLength else { return String(chars) }
        return String(chars[0..<wordEnd(chars, from: maxLength)]) + "…"
    }

    private static func wordStart(_ chars: [Character], from index: Int) -> Int {
        var i = index
        while i > 0, chars[i - 1] != " " { i -= 1 }
        return i
    }

    private static func wordEnd(_ chars: [Character], from index: Int) -> Int {
        var i = min(index, chars.count)
        while i < chars.count, chars[i] != " " { i += 1 }
        return i
    }
}
