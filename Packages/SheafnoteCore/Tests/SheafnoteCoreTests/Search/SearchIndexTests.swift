import XCTest
@testable import SheafnoteCore

final class SearchIndexTests: XCTestCase {
    private let nb = UUID()

    private func page(_ fields: [SearchField: String], id: UUID = UUID(), at t: TimeInterval = 0, fp: String = "1") -> SearchDocument {
        SearchDocument(id: SearchDocumentID(kind: .page, id: id), notebookID: nb, fields: fields,
                       modifiedAt: Date(timeIntervalSince1970: t), fingerprint: fp)
    }

    private func title(_ text: String, kind: SearchDocumentID.Kind = .notebookTitle, id: UUID = UUID()) -> SearchDocument {
        SearchDocument(id: SearchDocumentID(kind: kind, id: id), notebookID: kind == .notebookTitle ? id : nil,
                       fields: [.title: text], modifiedAt: .distantPast, fingerprint: "1")
    }

    func testFindsPageByHandwritingTypedAndPdfText() {
        var index = SearchIndex()
        let a = page([.handwriting: "integral of sine"])
        let b = page([.typed: "Gauss theorem"])
        let c = page([.pdf: "Chapter on entropy"])
        [a, b, c].forEach { index.upsert($0) }
        XCTAssertEqual(index.search("sine").map(\.documentID), [a.id])
        XCTAssertEqual(index.search("gauss").map(\.documentID), [b.id])
        XCTAssertEqual(index.search("entropy").map(\.documentID), [c.id])
        XCTAssertEqual(index.search("entropy").first?.field, .pdf)
    }

    func testAllTermsMustMatchButMayBeInDifferentFields() {
        var index = SearchIndex()
        let a = page([.typed: "alpha", .handwriting: "beta"])
        let b = page([.typed: "alpha only"])
        index.upsert(a)
        index.upsert(b)
        XCTAssertEqual(index.search("alpha beta").map(\.documentID), [a.id])
    }

    func testPrefixMatchesWhileTyping() {
        var index = SearchIndex()
        let a = page([.typed: "thermodynamics"])
        index.upsert(a)
        XCTAssertEqual(index.search("thermo").count, 1)
        XCTAssertEqual(index.search("thermodynamicsx").count, 0)
        XCTAssertEqual(index.search("hermo").count, 0)
    }

    func testTitleOutranksBodyText() {
        var index = SearchIndex()
        let body = page([.typed: "physics notes"])
        let named = title("Physics")
        index.upsert(body)
        index.upsert(named)
        XCTAssertEqual(index.search("physics").map(\.documentID), [named.id, body.id])
    }

    func testExactBeatsPrefix() {
        var index = SearchIndex()
        let prefix = page([.typed: "planetary"], at: 5)
        let exact = page([.typed: "planet"], at: 1)
        index.upsert(prefix)
        index.upsert(exact)
        XCTAssertEqual(index.search("planet").first?.documentID, exact.id)
    }

    func testAdjacentPhraseOutranksScatteredTerms() {
        var index = SearchIndex()
        let scattered = page([.typed: "quantum is a hard thing and mechanics too"], at: 9)
        let phrase = page([.typed: "quantum mechanics"], at: 1)
        index.upsert(scattered)
        index.upsert(phrase)
        XCTAssertEqual(index.search("quantum mechanics").first?.documentID, phrase.id)
    }

    func testEqualScoresPreferNewerDocument() {
        var index = SearchIndex()
        let old = page([.typed: "memo"], at: 1)
        let new = page([.typed: "memo"], at: 2)
        index.upsert(old)
        index.upsert(new)
        XCTAssertEqual(index.search("memo").map(\.documentID), [new.id, old.id])
    }

    func testUpsertReplacesAndRemoveDeletes() {
        var index = SearchIndex()
        let id = UUID()
        index.upsert(page([.typed: "old words"], id: id))
        index.upsert(page([.typed: "fresh words"], id: id, fp: "2"))
        XCTAssertTrue(index.search("old").isEmpty)
        XCTAssertEqual(index.search("fresh").count, 1)
        XCTAssertEqual(index.count, 1)
        index.remove(SearchDocumentID(kind: .page, id: id))
        XCTAssertTrue(index.search("fresh").isEmpty)
        XCTAssertEqual(index.count, 0)
    }

    func testFingerprintLookupSupportsSkippingUnchangedDocuments() {
        var index = SearchIndex()
        let doc = page([.typed: "x"], fp: "abc")
        index.upsert(doc)
        XCTAssertEqual(index.fingerprint(of: doc.id), "abc")
        XCTAssertNil(index.fingerprint(of: SearchDocumentID(kind: .page, id: UUID())))
    }

    func testRetainOnlyDropsUnlistedDocuments() {
        var index = SearchIndex()
        let keep = page([.typed: "keep"])
        let drop = page([.typed: "drop"])
        index.upsert(keep)
        index.upsert(drop)
        index.retainOnly(ids: [keep.id])
        XCTAssertEqual(index.count, 1)
        XCTAssertTrue(index.search("drop").isEmpty)
    }

    func testScopeToNotebook() {
        var index = SearchIndex()
        let other = UUID()
        let mine = page([.typed: "shared"])
        var theirs = page([.typed: "shared"])
        theirs.notebookID = other
        index.upsert(mine)
        index.upsert(theirs)
        XCTAssertEqual(index.search("shared", notebookID: nb).map(\.documentID), [mine.id])
    }

    func testBlankQueryAndLimit() {
        var index = SearchIndex()
        for i in 0..<10 { index.upsert(page([.typed: "word \(i)"])) }
        XCTAssertTrue(index.search("   ").isEmpty)
        XCTAssertEqual(index.search("word", limit: 3).count, 3)
    }

    func testSnippetHighlightsTheMatch() {
        var index = SearchIndex()
        index.upsert(page([.handwriting: "remember to buy milk tomorrow"]))
        let hit = index.search("milk").first
        XCTAssertEqual(hit?.snippet.text, "remember to buy milk tomorrow")
        XCTAssertEqual(hit?.snippet.ranges, [16..<20])
        XCTAssertEqual(hit?.terms, ["milk"])
    }

    func testManyDocumentsStayFast() {
        var index = SearchIndex()
        for i in 0..<3000 { index.upsert(page([.handwriting: "note number \(i) about topic\(i % 50)"])) }
        let start = Date()
        XCTAssertEqual(index.search("topic7").count, 60)
        XCTAssertLessThan(Date().timeIntervalSince(start), 0.5)
    }
}
