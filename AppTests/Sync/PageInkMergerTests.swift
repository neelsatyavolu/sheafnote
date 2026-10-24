import PencilKit
import Testing
import SheafnoteCore
@testable import Sheafnote

@Suite struct PageInkMergerTests {
    private let t0 = Date(timeIntervalSinceReferenceDate: 1_000)

    private func stroke(x: CGFloat, at seconds: Double) -> PKStroke {
        let points = (0..<2).map { i in
            PKStrokePoint(location: CGPoint(x: x + CGFloat(i) * 10, y: 5), timeOffset: Double(i) * 0.01,
                          size: CGSize(width: 3, height: 3), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        let path = PKStrokePath(controlPoints: points, creationDate: t0.addingTimeInterval(seconds))
        return PKStroke(ink: PKInk(.pen, color: .black), path: path)
    }

    /// An ink side built from (id, x, seconds) triples.
    private func side(_ items: [(String, CGFloat, Double)]) -> InkState {
        let drawing = PKDrawing(strokes: items.map { stroke(x: $0.1, at: $0.2) })
        return InkState(data: drawing.dataRepresentation(), strokeIDs: items.map(\.0))
    }

    private func xs(_ state: InkState) throws -> [CGFloat] {
        try PKDrawing(data: #require(state.data)).strokes.map { $0.path.first?.location.x ?? -1 }
    }

    private let merger = PageInkMerger()

    @Test func concurrentAdditionsProduceOneDrawingWithBothStrokes() throws {
        let base = ["a"]
        let ours = side([("a", 0, 0), ("b", 100, 2)])
        let theirs = side([("a", 0, 0), ("c", 200, 3)])
        let merged = try merger.merge(baseStrokeIDs: base, ours: ours, theirs: theirs)
        #expect(merged.strokeIDs == ["a", "b", "c"])
        #expect(try xs(merged) == [0, 100, 200])
    }

    @Test func concurrentDeletionsBothApply() throws {
        let merged = try merger.merge(baseStrokeIDs: ["a", "b", "c"],
                                      ours: side([("b", 100, 2), ("c", 200, 3)]),
                                      theirs: side([("a", 0, 1), ("c", 200, 3)]))
        #expect(merged.strokeIDs == ["c"])
        #expect(try xs(merged) == [200])
    }

    @Test func editedStrokeSurvivesTheOtherSidesDeletion() throws {
        // ours moved "a" (new id a2); theirs erased it.
        let merged = try merger.merge(baseStrokeIDs: ["a"], ours: side([("a2", 50, 5)]), theirs: side([]))
        #expect(merged.strokeIDs == ["a2"])
        #expect(try xs(merged) == [50])
    }

    @Test func emptySidesAndMissingBaseUnion() throws {
        let merged = try merger.merge(baseStrokeIDs: [], ours: InkState(data: nil, strokeIDs: []), theirs: side([("t", 7, 1)]))
        #expect(merged.strokeIDs == ["t"])
        let both = try merger.merge(baseStrokeIDs: [], ours: InkState(data: nil, strokeIDs: []), theirs: InkState(data: nil, strokeIDs: []))
        #expect(both.strokeIDs.isEmpty)
    }

    @Test func mergedDataHasNoDuplicateStrokes() throws {
        let same = side([("a", 0, 0), ("b", 10, 1)])
        let merged = try merger.merge(baseStrokeIDs: [], ours: same, theirs: same)
        #expect(merged.strokeIDs == ["a", "b"])
        #expect(try PKDrawing(data: #require(merged.data)).strokes.count == 2)
    }

    @Test func corruptServerInkThrows() {
        let corrupt = InkState(data: Data("nonsense".utf8), strokeIDs: ["z"])
        #expect(throws: InkMergeError.undecodable(side: "iCloud")) {
            try merger.merge(baseStrokeIDs: [], ours: side([("a", 0, 0)]), theirs: corrupt)
        }
    }

    @Test func corruptLocalInkThrows() {
        let corrupt = InkState(data: Data("nonsense".utf8), strokeIDs: ["z"])
        #expect(throws: InkMergeError.undecodable(side: "your")) {
            try merger.merge(baseStrokeIDs: [], ours: corrupt, theirs: side([("a", 0, 0)]))
        }
    }

    @Test func strokeIDsThatDoNotMatchTheDrawingThrow() {
        let misaligned = InkState(data: side([("a", 0, 0), ("b", 1, 1)]).data, strokeIDs: ["only-one"])
        #expect(throws: InkMergeError.undecodable(side: "iCloud")) {
            try merger.merge(baseStrokeIDs: [], ours: side([]), theirs: misaligned)
        }
    }

    @Test func missingDataButListedStrokesThrows() {
        #expect(throws: InkMergeError.self) {
            try merger.merge(baseStrokeIDs: [], ours: InkState(data: nil, strokeIDs: ["ghost"]), theirs: side([]))
        }
    }

    @Test func fiveThousandStrokesMergeQuickly() throws {
        let base = (0..<5_000).map { ("s\($0)", CGFloat($0), Double($0)) }
        let ours = side(Array(base.dropFirst(10)) + [("mine", 1, 6_000)])
        let theirs = side(Array(base.dropLast(10)) + [("theirs", 2, 7_000)])
        let clock = ContinuousClock()
        var merged: InkState?
        let elapsed = try clock.measure { merged = try merger.merge(baseStrokeIDs: base.map(\.0), ours: ours, theirs: theirs) }
        #expect(elapsed < .seconds(5))
        #expect(merged?.strokeIDs.count == 4_982)
    }
}
