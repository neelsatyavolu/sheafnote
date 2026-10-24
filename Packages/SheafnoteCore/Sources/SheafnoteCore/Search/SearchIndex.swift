import Foundation

/// In-memory inverted index over `SearchDocument`s. Every query word must match (as a word prefix, so results
/// appear while typing); matches in titles rank above typed text, then handwriting, then PDF text.
/// A value type: copy it to use it off the main actor.
public struct SearchIndex: Sendable {
    private struct Entry: Sendable {
        var document: SearchDocument
        var words: [SearchField: [String]]
    }

    private var entries: [SearchDocumentID: Entry] = [:]
    private var postings: [String: Set<SearchDocumentID>] = [:]
    private var sortedTerms: [String] = []

    public init() {}

    public var count: Int { entries.count }

    public func document(_ id: SearchDocumentID) -> SearchDocument? { entries[id]?.document }

    public func fingerprint(of id: SearchDocumentID) -> String? { entries[id]?.document.fingerprint }

    // MARK: Updating

    public mutating func upsert(_ document: SearchDocument) {
        remove(document.id)
        var words: [SearchField: [String]] = [:]
        for (field, text) in document.fields {
            let terms = SearchTokenizer.terms(in: text)
            if !terms.isEmpty { words[field] = terms }
        }
        entries[document.id] = Entry(document: document, words: words)
        for term in Set(words.values.joined()) { addPosting(term, document.id) }
    }

    public mutating func remove(_ id: SearchDocumentID) {
        guard let entry = entries.removeValue(forKey: id) else { return }
        for term in Set(entry.words.values.joined()) { removePosting(term, id) }
    }

    /// Drops every document whose id is not in `ids`.
    public mutating func retainOnly(ids: Set<SearchDocumentID>) {
        for id in entries.keys where !ids.contains(id) { remove(id) }
    }

    private mutating func addPosting(_ term: String, _ id: SearchDocumentID) {
        if postings[term] == nil {
            let at = lowerBound(of: term)
            sortedTerms.insert(term, at: at)
        }
        postings[term, default: []].insert(id)
    }

    private mutating func removePosting(_ term: String, _ id: SearchDocumentID) {
        postings[term]?.remove(id)
        guard postings[term]?.isEmpty == true else { return }
        postings[term] = nil
        let at = lowerBound(of: term)
        if at < sortedTerms.count, sortedTerms[at] == term { sortedTerms.remove(at: at) }
    }

    private func lowerBound(of term: String) -> Int {
        var low = 0
        var high = sortedTerms.count
        while low < high {
            let mid = (low + high) / 2
            if sortedTerms[mid] < term { low = mid + 1 } else { high = mid }
        }
        return low
    }

    // MARK: Searching

    public func search(_ query: String, notebookID: UUID? = nil, limit: Int = 200) -> [SearchHit] {
        var terms: [String] = []
        for term in SearchTokenizer.terms(in: query) where !terms.contains(term) { terms.append(term) }
        guard !terms.isEmpty, limit > 0 else { return [] }
        var hits: [(hit: SearchHit, modifiedAt: Date)] = []
        for id in candidates(for: terms) {
            guard let entry = entries[id] else { continue }
            if let notebookID, entry.document.notebookID != notebookID { continue }
            hits.append((makeHit(entry, terms: terms), entry.document.modifiedAt))
        }
        hits.sort(by: Self.isBefore)
        return hits.prefix(limit).map(\.hit)
    }

    private func candidates(for terms: [String]) -> Set<SearchDocumentID> {
        var result: Set<SearchDocumentID>?
        for term in terms {
            var matching = Set<SearchDocumentID>()
            var i = lowerBound(of: term)
            while i < sortedTerms.count, sortedTerms[i].hasPrefix(term) {
                matching.formUnion(postings[sortedTerms[i]] ?? [])
                i += 1
            }
            result = result.map { $0.intersection(matching) } ?? matching
            if result?.isEmpty == true { return [] }
        }
        return result ?? []
    }

    private func makeHit(_ entry: Entry, terms: [String]) -> SearchHit {
        var total = 0.0
        var bestField = SearchField.title
        var bestFieldScore = -1.0
        for (field, words) in entry.words {
            let score = fieldScore(words, field: field, terms: terms)
            total += score
            if score > bestFieldScore || (score == bestFieldScore && field.rawValue < bestField.rawValue) {
                bestField = field
                bestFieldScore = score
            }
        }
        let text = entry.document.fields[bestField] ?? ""
        return SearchHit(documentID: entry.document.id, notebookID: entry.document.notebookID, field: bestField,
                         score: total, snippet: SnippetBuilder.snippet(in: text, terms: terms), terms: terms)
    }

    private func fieldScore(_ words: [String], field: SearchField, terms: [String]) -> Double {
        var score = 0.0
        for term in terms {
            var exact = 0
            var prefix = 0
            for word in words where word.hasPrefix(term) {
                if word.count == term.count { exact += 1 } else { prefix += 1 }
            }
            guard exact + prefix > 0 else { continue }
            let strength = exact > 0 ? 1.0 : 0.6
            score += field.weight * strength * (1 + log(Double(exact + prefix)))
        }
        if terms.count > 1, containsPhrase(words, terms: terms) { score += 2 * field.weight }
        return score
    }

    private func containsPhrase(_ words: [String], terms: [String]) -> Bool {
        guard words.count >= terms.count else { return false }
        for start in 0...(words.count - terms.count) {
            if terms.indices.allSatisfy({ words[start + $0].hasPrefix(terms[$0]) }) { return true }
        }
        return false
    }

    private static func isBefore(_ a: (hit: SearchHit, modifiedAt: Date), _ b: (hit: SearchHit, modifiedAt: Date)) -> Bool {
        if a.hit.score != b.hit.score { return a.hit.score > b.hit.score }
        if a.modifiedAt != b.modifiedAt { return a.modifiedAt > b.modifiedAt }
        return a.hit.documentID.id.uuidString < b.hit.documentID.id.uuidString
    }
}
