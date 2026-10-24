import Foundation
import Testing
@testable import SheafnoteCore

@Suite struct StrokeMergerTests {
    private func e(_ id: String, _ t: Double = 0) -> StrokeEntry {
        StrokeEntry(id: StrokeID(rawValue: id), creationDate: Date(timeIntervalSinceReferenceDate: t))
    }
    private func ids(_ r: MergeResult) -> [String] { r.ordered.map(\.id.rawValue) }

    @Test func concurrentAdditionsAreUnioned() {
        let base = [e("a", 1)]
        let r = StrokeMerger.merge(base: base, ours: base + [e("b", 2)], theirs: base + [e("c", 3)])
        #expect(ids(r) == ["a", "b", "c"])
        #expect(r.addedFromTheirs == 1 && r.removedByTheirs == 0)
        #expect(r.ordered.first { $0.id.rawValue == "c" }?.from == .theirs)
        #expect(r.ordered.first { $0.id.rawValue == "b" }?.from == .ours)
    }

    @Test func concurrentDeletionsBothApply() {
        let base = [e("a", 1), e("b", 2), e("c", 3)]
        let r = StrokeMerger.merge(base: base, ours: [e("b", 2), e("c", 3)], theirs: [e("a", 1), e("c", 3)])
        #expect(ids(r) == ["c"])
        #expect(r.removedByTheirs == 1)
    }

    @Test func deleteOnOneSideBeatsKeepOnOther() {
        let base = [e("a", 1), e("b", 2)]
        #expect(ids(StrokeMerger.merge(base: base, ours: base, theirs: [e("b", 2)])) == ["b"])
        #expect(ids(StrokeMerger.merge(base: base, ours: [e("a", 1)], theirs: base)) == ["a"])
    }

    @Test func deleteVersusEditKeepsTheEditAndDropsTheOriginal() {
        // An edit (recolor, move) is delete old + add new. Ours edits a -> a2, theirs leaves a alone and adds b.
        let base = [e("a", 1)]
        let r = StrokeMerger.merge(base: base, ours: [e("a2", 5)], theirs: [e("a", 1), e("b", 6)])
        #expect(ids(r) == ["a2", "b"])
    }

    @Test func bothSidesEditTheSameStrokeDifferentlyKeepsBothEdits() {
        let r = StrokeMerger.merge(base: [e("a", 1)], ours: [e("a-ours", 5)], theirs: [e("a-theirs", 6)])
        #expect(ids(r) == ["a-ours", "a-theirs"])
    }

    @Test func identicalEditsCollapseToOneStroke() {
        let edited = [e("a2", 5)]
        let r = StrokeMerger.merge(base: [e("a", 1)], ours: edited, theirs: edited)
        #expect(ids(r) == ["a2"])
        #expect(r.addedFromTheirs == 0)
        #expect(r.ordered.first?.from == .ours)
    }

    @Test func sameStrokeOnBothSidesIsNotDuplicated() {
        #expect(ids(StrokeMerger.merge(base: [], ours: [e("x", 1)], theirs: [e("x", 1)])) == ["x"])
    }

    @Test func emptyBaseUnionsEverything() {
        let r = StrokeMerger.merge(base: [], ours: [e("b", 2)], theirs: [e("a", 1)])
        #expect(ids(r) == ["a", "b"])
        #expect(r.removedByTheirs == 0)
    }

    @Test func allEmptyGivesEmpty() {
        #expect(StrokeMerger.merge(base: [], ours: [], theirs: []).ordered.isEmpty)
    }

    @Test func orderingBreaksTiesByID() {
        let r = StrokeMerger.merge(base: [], ours: [e("z", 1), e("m", 1)], theirs: [e("a", 1)])
        #expect(ids(r) == ["a", "m", "z"])
    }

    @Test func duplicateInputIDsAreCollapsed() {
        #expect(ids(StrokeMerger.merge(base: [], ours: [e("a", 1), e("a", 1)], theirs: [])) == ["a"])
    }

    @Test func bothSidesDeleteEverything() {
        let base = [e("a", 1), e("b", 2)]
        #expect(StrokeMerger.merge(base: base, ours: [], theirs: []).ordered.isEmpty)
    }

    @Test func largeMergeStaysFast() {
        let base = (0..<5_000).map { e("s\($0)", Double($0)) }
        func index(_ x: StrokeEntry) -> Int { Int(x.id.rawValue.dropFirst()) ?? 0 }
        let ours = base.filter { index($0) % 7 != 0 } + (0..<200).map { e("o\($0)", 6_000 + Double($0)) }
        let theirs = base.filter { index($0) % 11 != 0 } + (0..<200).map { e("t\($0)", 7_000 + Double($0)) }
        let clock = ContinuousClock()
        var result: MergeResult?
        let elapsed = clock.measure { result = StrokeMerger.merge(base: base, ours: ours, theirs: theirs) }
        #expect(elapsed < .milliseconds(200))
        let kept = Set(result?.ordered.map(\.id.rawValue) ?? [])
        #expect(!kept.contains("s0") && !kept.contains("s11") && kept.contains("s1") && kept.contains("t199"))
    }
}
