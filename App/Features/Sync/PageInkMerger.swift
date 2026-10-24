import Foundation
import PencilKit
import SheafnoteCore

/// Three-way merge of page ink with real `PKDrawing`s. Decodes both sides, lets `StrokeMerger` decide which stroke
/// ids survive, and rebuilds one drawing from the surviving `PKStroke`s. Throws instead of guessing when either
/// side cannot be decoded or its stroke ids do not line up with its strokes, so the caller keeps both versions.
struct PageInkMerger: InkMerging {
    func merge(baseStrokeIDs: [String], ours: InkState, theirs: InkState) throws -> InkState {
        let mine = try strokes(of: ours, side: "your")
        let server = try strokes(of: theirs, side: "iCloud")
        let base = baseStrokeIDs.map { StrokeEntry(id: StrokeID(rawValue: $0), creationDate: .distantPast) }
        let result = StrokeMerger.merge(base: base, ours: mine.entries, theirs: server.entries)
        let chosen = result.ordered.compactMap { item in
            (item.from == .ours ? mine.byID : server.byID)[item.id]
        }
        let drawing = PKDrawing(strokes: chosen)
        return InkState(data: drawing.dataRepresentation(), strokeIDs: result.ordered.map(\.id.rawValue))
    }

    private struct SideStrokes {
        var entries: [StrokeEntry] = []
        var byID: [StrokeID: PKStroke] = [:]
    }

    private func strokes(of state: InkState, side: String) throws -> SideStrokes {
        guard let data = state.data, !data.isEmpty else {
            guard state.strokeIDs.isEmpty else { throw InkMergeError.undecodable(side: side) }
            return SideStrokes()
        }
        let drawing: PKDrawing
        do { drawing = try PKDrawing(data: data) } catch { throw InkMergeError.undecodable(side: side) }
        guard drawing.strokes.count == state.strokeIDs.count else { throw InkMergeError.undecodable(side: side) }
        var result = SideStrokes()
        for (raw, stroke) in zip(state.strokeIDs, drawing.strokes) {
            let id = StrokeID(rawValue: raw)
            guard result.byID[id] == nil else { continue }   // an exact duplicate stroke collapses to one
            result.entries.append(StrokeEntry(id: id, creationDate: stroke.path.creationDate))
            result.byID[id] = stroke
        }
        return result
    }
}
